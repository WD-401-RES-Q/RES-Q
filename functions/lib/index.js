"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.cleanupOldReports = exports.migrateToEncrypted = exports.getDecryptedUsers = exports.decryptUserData = exports.registerUserEncrypted = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");
admin.initializeApp();
const db = admin.firestore();
// PII fields that should be encrypted
const PII_FIELDS = [
    'fullName',
    'email',
    'address',
    'dateOfBirth',
    'contactNumber'
];
/**
 * AES-256-GCM Encryption using Node.js crypto
 */
class EncryptionHelper {
    static getMasterKey() {
        var _a;
        // Master key should be stored in Firebase environment config
        // Set it using: firebase functions:config:set encryption.masterkey="your-base64-encoded-32-byte-key"
        const masterKeyBase64 = (_a = functions.config().encryption) === null || _a === void 0 ? void 0 : _a.masterkey;
        if (!masterKeyBase64) {
            // Generate a deterministic key for development (CHANGE IN PRODUCTION!)
            console.warn('WARNING: Using default encryption key. Set encryption.masterkey in production!');
            return crypto.scryptSync('resq-default-dev-key', 'resq-salt', 32);
        }
        return Buffer.from(masterKeyBase64, 'base64');
    }
    static encrypt(plaintext) {
        const key = this.getMasterKey();
        const iv = crypto.randomBytes(12); // 96 bits for GCM
        const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
        let encrypted = cipher.update(plaintext, 'utf8');
        encrypted = Buffer.concat([encrypted, cipher.final()]);
        const authTag = cipher.getAuthTag();
        // Combine: IV (12 bytes) + AuthTag (16 bytes) + Encrypted Data
        const combined = Buffer.concat([iv, authTag, encrypted]);
        return combined.toString('base64');
    }
    static decrypt(ciphertext) {
        const key = this.getMasterKey();
        const combined = Buffer.from(ciphertext, 'base64');
        // Extract components
        const iv = combined.subarray(0, 12);
        const authTag = combined.subarray(12, 28);
        const encrypted = combined.subarray(28);
        const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
        decipher.setAuthTag(authTag);
        let decrypted = decipher.update(encrypted);
        decrypted = Buffer.concat([decrypted, decipher.final()]);
        return decrypted.toString('utf8');
    }
    static encryptUserData(userData) {
        const encrypted = Object.assign({}, userData);
        for (const field of PII_FIELDS) {
            if (encrypted[field] && typeof encrypted[field] === 'string') {
                encrypted[field] = this.encrypt(encrypted[field]);
                encrypted[`${field}_encrypted`] = true;
            }
        }
        encrypted['_encryptedAt'] = admin.firestore.FieldValue.serverTimestamp();
        return encrypted;
    }
    static decryptUserData(userData) {
        const decrypted = Object.assign({}, userData);
        for (const field of PII_FIELDS) {
            if (decrypted[field] && decrypted[`${field}_encrypted`]) {
                try {
                    decrypted[field] = this.decrypt(decrypted[field]);
                }
                catch (error) {
                    console.error(`Failed to decrypt field ${field}:`, error);
                    decrypted[field] = '[Decryption Failed]';
                }
            }
        }
        return decrypted;
    }
}
/**
 * Cloud Function to register a new user with encrypted PII
 * Called from the mobile app during registration
 */
exports.registerUserEncrypted = functions
    .region('asia-east2')
    .https.onCall(async (data, context) => {
    try {
        const userData = data;
        // Validate required fields
        if (!userData.contactNumber) {
            throw new functions.https.HttpsError('invalid-argument', 'Contact number is required');
        }
        // Check if phone already exists
        const phoneNumber = userData.contactNumber;
        const pendingQuery = await db.collection('pending_users')
            .where('contactNumber', '==', phoneNumber)
            .limit(1)
            .get();
        if (!pendingQuery.empty) {
            throw new functions.https.HttpsError('already-exists', 'This phone number is already registered');
        }
        const approvedQuery = await db.collection('approved_users')
            .where('contactNumber', '==', phoneNumber)
            .limit(1)
            .get();
        if (!approvedQuery.empty) {
            throw new functions.https.HttpsError('already-exists', 'This phone number is already registered');
        }
        // Encrypt PII fields
        const encryptedUserData = EncryptionHelper.encryptUserData(userData);
        // Add metadata
        encryptedUserData['registeredAt'] = admin.firestore.FieldValue.serverTimestamp();
        encryptedUserData['status'] = 'pending';
        // Store in pending_users collection
        const docRef = await db.collection('pending_users').add(encryptedUserData);
        console.log(`User registered with encrypted data: ${docRef.id}`);
        return {
            success: true,
            userId: docRef.id,
            message: 'Registration successful. Pending admin approval.'
        };
    }
    catch (error) {
        console.error('Registration error:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', 'Failed to register user');
    }
});
/**
 * Cloud Function to decrypt user data for admin viewing
 * Only callable by authenticated admins
 */
exports.decryptUserData = functions
    .region('asia-east2')
    .https.onCall(async (data, context) => {
    try {
        const { userId, collection: collectionName, adminId } = data;
        // Verify admin exists
        const adminDoc = await db.collection('admins').doc(adminId).get();
        if (!adminDoc.exists) {
            throw new functions.https.HttpsError('permission-denied', 'Admin not found');
        }
        // Get user document
        const userDoc = await db.collection(collectionName).doc(userId).get();
        if (!userDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'User not found');
        }
        const userData = userDoc.data();
        // Decrypt PII fields
        const decryptedData = EncryptionHelper.decryptUserData(userData);
        decryptedData['id'] = userId;
        return {
            success: true,
            userData: decryptedData
        };
    }
    catch (error) {
        console.error('Decryption error:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', 'Failed to decrypt user data');
    }
});
/**
 * Cloud Function to get all users with decrypted data (for admin)
 */
exports.getDecryptedUsers = functions
    .region('asia-east2')
    .https.onCall(async (data, context) => {
    try {
        const { collection: collectionName, adminId } = data;
        // Verify admin exists
        const adminDoc = await db.collection('admins').doc(adminId).get();
        if (!adminDoc.exists) {
            throw new functions.https.HttpsError('permission-denied', 'Admin not found');
        }
        // Get all users from collection
        const snapshot = await db.collection(collectionName).get();
        const users = snapshot.docs.map((doc) => {
            const userData = doc.data();
            const decryptedData = EncryptionHelper.decryptUserData(userData);
            decryptedData['id'] = doc.id;
            return decryptedData;
        });
        return {
            success: true,
            users
        };
    }
    catch (error) {
        console.error('Get decrypted users error:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', 'Failed to get users');
    }
});
/**
 * Cloud Function to migrate existing unencrypted user data to encrypted format
 * Run this once to encrypt existing data
 */
exports.migrateToEncrypted = functions
    .region('asia-east2')
    .https.onCall(async (data, context) => {
    try {
        const { adminId } = data;
        // Verify admin
        const adminDoc = await db.collection('admins').doc(adminId).get();
        if (!adminDoc.exists) {
            throw new functions.https.HttpsError('permission-denied', 'Admin not found');
        }
        const collections = ['pending_users', 'approved_users', 'rejected_users'];
        let totalMigrated = 0;
        for (const collectionName of collections) {
            const snapshot = await db.collection(collectionName).get();
            for (const doc of snapshot.docs) {
                const userData = doc.data();
                // Skip if already encrypted
                if (userData['_encryptedAt']) {
                    continue;
                }
                // Encrypt and update
                const encryptedData = EncryptionHelper.encryptUserData(userData);
                await doc.ref.update(encryptedData);
                totalMigrated++;
            }
        }
        return {
            success: true,
            message: `Migrated ${totalMigrated} user records to encrypted format`
        };
    }
    catch (error) {
        console.error('Migration error:', error);
        throw new functions.https.HttpsError('internal', 'Migration failed');
    }
});
/**
 * Scheduled function that runs daily at midnight (Asia/Manila time)
 * Deletes reports older than 30 days from the database
 */
exports.cleanupOldReports = functions
    .region('asia-east2')
    .pubsub
    .schedule('0 0 * * *')
    .timeZone('Asia/Manila')
    .onRun(async (context) => {
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    const reportsRef = db.collection('reports');
    // Query reports older than 30 days based on reportedAt timestamp
    const oldReportsQuery = reportsRef.where('reportedAt', '<', thirtyDaysAgo);
    const snapshot = await oldReportsQuery.get();
    if (snapshot.empty) {
        console.log('No reports older than 30 days found.');
        return null;
    }
    // Firestore batch has a limit of 500 operations
    const batchSize = 500;
    let totalDeleted = 0;
    // Process in batches if there are many documents
    for (let i = 0; i < snapshot.docs.length; i += batchSize) {
        const batch = db.batch();
        const batchDocs = snapshot.docs.slice(i, i + batchSize);
        batchDocs.forEach((doc) => {
            batch.delete(doc.ref);
        });
        await batch.commit();
        totalDeleted += batchDocs.length;
    }
    console.log(`Deleted ${totalDeleted} reports older than 30 days.`);
    return null;
});
//# sourceMappingURL=index.js.map
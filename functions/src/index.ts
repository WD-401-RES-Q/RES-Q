import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';

admin.initializeApp();

const db = admin.firestore();

// PII fields that should be encrypted
const PII_FIELDS = [
  'fullName',
  'email',
  'address',
  'dateOfBirth',
  'contactNumber',
  'password',
  'pin'
];

const ENCRYPTION_VERSION = 'aes-256-gcm-v2-compat';
const DISPLAY_NAME_FIELD = 'displayName';

/**
 * AES-256-GCM Encryption using Node.js crypto
 */
class EncryptionHelper {
  private static readonly CIPHER_SUFFIX = '_cipher';
  private static readonly HASH_SUFFIX = '_hash';

  private static isNonEmptyString(value: unknown): value is string {
    return typeof value === 'string' && value.trim().length > 0;
  }

  private static cipherField(field: string): string {
    return `${field}${this.CIPHER_SUFFIX}`;
  }

  private static hashField(field: string): string {
    return `${field}${this.HASH_SUFFIX}`;
  }

  private static hashValue(value: string): string {
    return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
  }

  private static looksLikeCiphertext(value: string): boolean {
    const trimmed = value.trim();
    if (trimmed.length < 40) {
      return false;
    }

    // AES-GCM payloads are stored as base64 (IV + authTag + ciphertext)
    return /^[A-Za-z0-9+/=]+$/.test(trimmed) && !trimmed.includes(' ');
  }

  static hashForLookup(value: string): string {
    return this.hashValue(value);
  }

  private static getMasterKey(): Buffer {
    // Master key should be stored in Firebase environment config
    // Set it using: firebase functions:config:set encryption.masterkey="your-base64-encoded-32-byte-key"
    const masterKeyBase64 = functions.config().encryption?.masterkey;
    
    if (!masterKeyBase64) {
      // Generate a deterministic key for development (CHANGE IN PRODUCTION!)
      console.warn('WARNING: Using default encryption key. Set encryption.masterkey in production!');
      return crypto.scryptSync('resq-default-dev-key', 'resq-salt', 32);
    }
    
    return Buffer.from(masterKeyBase64, 'base64');
  }

  static encrypt(plaintext: string): string {
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

  static decrypt(ciphertext: string): string {
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

  static encryptUserData(userData: Record<string, unknown>): Record<string, unknown> {
    const encrypted = { ...userData };

    for (const field of PII_FIELDS) {
      const value = encrypted[field];
      const cipherField = this.cipherField(field);
      const hashField = this.hashField(field);
      const encryptedFlagField = `${field}_encrypted`;

      if (this.isNonEmptyString(value)) {
        // Compatibility mode:
        // Keep plaintext fields for existing mobile/web query flows,
        // while storing AES-256-GCM encrypted mirrors for defense/security proof.
        encrypted[cipherField] = this.encrypt(value);
        encrypted[hashField] = this.hashValue(value);
        encrypted[encryptedFlagField] = true;
      } else {
        delete encrypted[cipherField];
        delete encrypted[hashField];
        delete encrypted[encryptedFlagField];
      }
    }

    encrypted['_encryptedAt'] = admin.firestore.FieldValue.serverTimestamp();
    encrypted['_encryptionVersion'] = ENCRYPTION_VERSION;
    return encrypted;
  }

  static normalizeLegacyUserData(userData: Record<string, unknown>): Record<string, unknown> {
    const normalized = { ...userData };

    for (const field of PII_FIELDS) {
      const cipherField = this.cipherField(field);
      const encryptedFlagField = `${field}_encrypted`;
      const hasTopLevelField = Object.prototype.hasOwnProperty.call(normalized, field);
      const topLevelValue = normalized[field];
      const hasTopLevelString = this.isNonEmptyString(topLevelValue);
      const topLevelLooksCiphertext = hasTopLevelString
        ? this.looksLikeCiphertext(topLevelValue)
        : false;

      const mirroredCipherValue = normalized[cipherField];
      // Keep modern plaintext fields intact. Only auto-decrypt mirrored values
      // when top-level data looks like legacy ciphertext.
      if (
        hasTopLevelField &&
        topLevelLooksCiphertext &&
        this.isNonEmptyString(mirroredCipherValue)
      ) {
        try {
          normalized[field] = this.decrypt(mirroredCipherValue);
          continue;
        } catch (error) {
          console.error(`Failed to decrypt mirrored field ${field}:`, error);
        }
      }

      // Backward compatibility for legacy v1 format where the top-level field
      // itself may contain ciphertext and <field>_encrypted is true.
      if (
        normalized[encryptedFlagField] &&
        hasTopLevelString &&
        topLevelLooksCiphertext
      ) {
        try {
          normalized[field] = this.decrypt(normalized[field] as string);
        } catch {
          // Keep original value if it was already plaintext.
        }
      }
    }

    return normalized;
  }

  static buildEncryptionFieldUpdates(
    afterData: Record<string, unknown>,
    beforeData?: Record<string, unknown>,
  ): Record<string, unknown> {
    const updates: Record<string, unknown> = {};
    let hasChanges = false;

    for (const field of PII_FIELDS) {
      const value = afterData[field];
      let beforeValue = beforeData?.[field];
      const cipherField = this.cipherField(field);
      const hashField = this.hashField(field);
      const encryptedFlagField = `${field}_encrypted`;

      if (!this.isNonEmptyString(beforeValue) && beforeData && this.isNonEmptyString(beforeData[cipherField])) {
        try {
          beforeValue = this.decrypt(beforeData[cipherField] as string);
        } catch {
          // Ignore and keep fallback comparison value.
        }
      }

      if (this.isNonEmptyString(value)) {
        const plaintextHash = this.hashValue(value);
        const storedHash = typeof afterData[hashField] === 'string'
          ? afterData[hashField] as string
          : '';
        const hasCipher = this.isNonEmptyString(afterData[cipherField]);
        const hasEncryptedFlag = afterData[encryptedFlagField] === true;
        const plaintextChanged = beforeData
          ? value !== beforeValue
          : false;

        if (plaintextChanged || !hasCipher || storedHash !== plaintextHash || !hasEncryptedFlag) {
          updates[cipherField] = this.encrypt(value);
          updates[hashField] = plaintextHash;
          updates[encryptedFlagField] = true;
          hasChanges = true;
        }
      } else {
        const hasCipher = afterData[cipherField] != null;
        const hasHash = afterData[hashField] != null;
        const hasEncryptedFlag = afterData[encryptedFlagField] != null;

        if (hasCipher || hasHash || hasEncryptedFlag) {
          updates[cipherField] = admin.firestore.FieldValue.delete();
          updates[hashField] = admin.firestore.FieldValue.delete();
          updates[encryptedFlagField] = admin.firestore.FieldValue.delete();
          hasChanges = true;
        }
      }
    }

    if (hasChanges) {
      updates['_encryptedAt'] = admin.firestore.FieldValue.serverTimestamp();
      updates['_encryptionVersion'] = ENCRYPTION_VERSION;
    }

    return updates;
  }

  static buildPlaintextFieldRestoreUpdates(
    normalizedData: Record<string, unknown>,
    currentData: Record<string, unknown>,
  ): Record<string, unknown> {
    const updates: Record<string, unknown> = {};
    for (const field of PII_FIELDS) {
      const normalizedValue = normalizedData[field];
      const currentValue = currentData[field];

      if (this.isNonEmptyString(normalizedValue) && currentValue !== normalizedValue) {
        updates[field] = normalizedValue;
      }
    }
    return updates;
  }

  static buildEncryptionArtifactDeleteUpdates(): Record<string, unknown> {
    const updates: Record<string, unknown> = {};
    for (const field of PII_FIELDS) {
      updates[this.cipherField(field)] = admin.firestore.FieldValue.delete();
      updates[this.hashField(field)] = admin.firestore.FieldValue.delete();
      updates[`${field}_encrypted`] = admin.firestore.FieldValue.delete();
    }
    updates['_encryptedAt'] = admin.firestore.FieldValue.delete();
    updates['_encryptionVersion'] = admin.firestore.FieldValue.delete();
    return updates;
  }

  static stripEncryptionArtifacts(userData: Record<string, unknown>): Record<string, unknown> {
    const cleaned = { ...userData };
    for (const field of PII_FIELDS) {
      delete cleaned[this.cipherField(field)];
      delete cleaned[this.hashField(field)];
      delete cleaned[`${field}_encrypted`];
    }
    delete cleaned['_encryptedAt'];
    delete cleaned['_encryptionVersion'];
    return cleaned;
  }

  static decryptUserData(userData: Record<string, unknown>): Record<string, unknown> {
    const decrypted = { ...userData };
    
    for (const field of PII_FIELDS) {
      const cipherField = this.cipherField(field);
      const topLevelValue = decrypted[field];
      const hasTopLevelString = this.isNonEmptyString(topLevelValue);

      // If top-level value is already readable plaintext, trust it.
      if (hasTopLevelString && !this.looksLikeCiphertext(topLevelValue)) {
        continue;
      }

      if (this.isNonEmptyString(decrypted[cipherField])) {
        try {
          decrypted[field] = this.decrypt(decrypted[cipherField] as string);
          continue;
        } catch (error) {
          console.error(`Failed to decrypt mirrored field ${field}:`, error);
          decrypted[field] = '[Decryption Failed]';
          continue;
        }
      }

      if (decrypted[field] && decrypted[`${field}_encrypted`]) {
        try {
          decrypted[field] = this.decrypt(decrypted[field] as string);
        } catch (error) {
          console.error(`Failed to decrypt field ${field}:`, error);
          decrypted[field] = '[Decryption Failed]';
        }
      }
    }
    
    return decrypted;
  }
}

/**
 * Cloud Function to register a new user in pending_users.
 * Pending accounts are stored as plaintext for admin review.
 * Encryption is enforced once the account is moved to approved_users.
 */
export const registerUserEncrypted = functions
  .region('asia-east2')
  .https.onCall(async (data, context) => {
    try {
      const payload = { ...(data as Record<string, unknown>) };
      
      // Validate required fields
      const contactNumberRaw = payload.contactNumber;
      if (!contactNumberRaw || typeof contactNumberRaw !== 'string') {
        throw new functions.https.HttpsError(
          'invalid-argument',
          'Contact number is required'
        );
      }

      const phoneNumber = contactNumberRaw.trim();
      if (!phoneNumber) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          'Contact number is required'
        );
      }

      // Optional: allow caller to set specific document ID (UID) for idempotent writes.
      const uid = typeof payload.uid === 'string' && payload.uid.trim().length > 0
        ? payload.uid.trim()
        : null;
      delete payload.uid;
      const phoneHash = EncryptionHelper.hashForLookup(phoneNumber);

      // Check if phone already exists
      const pendingQueries = await Promise.all([
        db.collection('pending_users')
          .where('contactNumber_hash', '==', phoneHash)
          .limit(5)
          .get(),
        db.collection('pending_users')
          .where('contactNumber', '==', phoneNumber)
          .limit(5)
          .get(),
      ]);
      
      const pendingIds = new Set<string>();
      const pendingDocs = pendingQueries.flatMap((querySnapshot) => querySnapshot.docs)
        .filter((doc) => {
          if (pendingIds.has(doc.id)) {
            return false;
          }
          pendingIds.add(doc.id);
          return true;
        });
      const phoneExistsInPending = pendingDocs.some((doc) => uid == null || doc.id !== uid);
      if (phoneExistsInPending) {
        throw new functions.https.HttpsError(
          'already-exists',
          'This phone number is already registered'
        );
      }

      const approvedQueries = await Promise.all([
        db.collection('approved_users')
          .where('contactNumber_hash', '==', phoneHash)
          .limit(1)
          .get(),
        db.collection('approved_users')
          .where('contactNumber', '==', phoneNumber)
          .limit(1)
          .get(),
      ]);
      
      if (approvedQueries.some((querySnapshot) => !querySnapshot.empty)) {
        throw new functions.https.HttpsError(
          'already-exists',
          'This phone number is already registered'
        );
      }

      // Normalize user payload and keep plaintext in pending_users.
      const normalizedUserData = EncryptionHelper.normalizeLegacyUserData(payload);
      normalizedUserData.contactNumber = phoneNumber;
      const pendingUserData: Record<string, unknown> = { ...normalizedUserData };
      pendingUserData.contactNumber_hash = phoneHash;
      if (typeof normalizedUserData.fullName === 'string' && normalizedUserData.fullName.trim().length > 0) {
        pendingUserData[DISPLAY_NAME_FIELD] = normalizedUserData.fullName.trim();
      }
      
      // Add metadata
      pendingUserData['registeredAt'] = admin.firestore.FieldValue.serverTimestamp();
      pendingUserData['status'] = 'pending';
      pendingUserData['accountStatus'] = 'pending';
      pendingUserData['createdAt'] = admin.firestore.FieldValue.serverTimestamp();
      if (!pendingUserData['pinCreatedAt']) {
        pendingUserData['pinCreatedAt'] = admin.firestore.FieldValue.serverTimestamp();
      }
      const cleanupEncryptionArtifacts = EncryptionHelper.buildEncryptionArtifactDeleteUpdates();
      const pendingWritePayload: Record<string, unknown> = {
        ...cleanupEncryptionArtifacts,
        ...pendingUserData,
      };

      // Store in pending_users collection
      let userId: string;
      if (uid) {
        await db.collection('pending_users').doc(uid).set(pendingWritePayload, { merge: true });
        userId = uid;
      } else {
        const docRef = await db.collection('pending_users').add(pendingWritePayload);
        userId = docRef.id;
      }
      
      console.log(`User registered in pending_users (plaintext pending flow): ${userId}`);
      
      return { 
        success: true, 
        userId,
        message: 'Registration successful. Pending admin approval.'
      };
    } catch (error) {
      console.error('Registration error:', error);
      
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      
      throw new functions.https.HttpsError(
        'internal',
        'Failed to register user'
      );
    }
  });

/**
 * Cloud Function to decrypt user data for admin viewing
 * Only callable by authenticated admins
 */
export const decryptUserData = functions
  .region('asia-east2')
  .https.onCall(async (data, context) => {
    try {
      const { userId, collection: collectionName, adminId } = data as {
        userId: string;
        collection: string;
        adminId: string;
      };

      // Verify admin exists
      const adminDoc = await db.collection('admins').doc(adminId).get();
      if (!adminDoc.exists) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'Admin not found'
        );
      }

      // Get user document
      const userDoc = await db.collection(collectionName).doc(userId).get();
      if (!userDoc.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          'User not found'
        );
      }

      const userData = userDoc.data() as Record<string, unknown>;
      
      // Decrypt PII fields
      const decryptedData = EncryptionHelper.decryptUserData(userData);
      decryptedData['id'] = userId;

      return { 
        success: true, 
        userData: decryptedData 
      };
    } catch (error) {
      console.error('Decryption error:', error);
      
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      
      throw new functions.https.HttpsError(
        'internal',
        'Failed to decrypt user data'
      );
    }
  });

/**
 * Cloud Function for end-users to fetch their own decrypted profile data.
 * Uses contact-number ownership checks to work with the app's phone-first auth flow.
 */
export const getOwnDecryptedProfile = functions
  .region('asia-east2')
  .https.onCall(async (data, context) => {
    try {
      if (!context.auth) {
        throw new functions.https.HttpsError(
          'unauthenticated',
          'Authentication is required',
        );
      }

      const payload = (data ?? {}) as {
        contactNumber?: string;
        docId?: string;
      };

      const contactNumber = typeof payload.contactNumber === 'string'
        ? payload.contactNumber.trim()
        : '';
      const docId = typeof payload.docId === 'string'
        ? payload.docId.trim()
        : '';

      if (contactNumber.length === 0) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          'contactNumber is required',
        );
      }

      const normalizePhone = (value: string): string => value.replace(/[^0-9]/g, '');
      const normalizedContactNumber = normalizePhone(contactNumber);
      if (normalizedContactNumber.length === 0) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          'contactNumber is invalid',
        );
      }

      const phoneCandidates = new Set<string>();
      phoneCandidates.add(contactNumber);
      phoneCandidates.add(normalizedContactNumber);
      if (normalizedContactNumber.startsWith('63')) {
        phoneCandidates.add(`+${normalizedContactNumber}`);
        if (normalizedContactNumber.length === 12) {
          phoneCandidates.add(`0${normalizedContactNumber.substring(2)}`);
        }
      } else if (normalizedContactNumber.length === 10) {
        phoneCandidates.add(`+63${normalizedContactNumber}`);
        phoneCandidates.add(`0${normalizedContactNumber}`);
      } else if (
        normalizedContactNumber.startsWith('0') &&
        normalizedContactNumber.length === 11
      ) {
        const local = normalizedContactNumber.substring(1);
        phoneCandidates.add(`+63${local}`);
        phoneCandidates.add(`63${local}`);
      }

      const normalizedCandidateSet = new Set<string>();
      const phoneHashes = new Set<string>();
      for (const candidate of phoneCandidates) {
        const trimmed = candidate.trim();
        if (trimmed.length === 0) {
          continue;
        }
        normalizedCandidateSet.add(normalizePhone(trimmed));
        phoneHashes.add(EncryptionHelper.hashForLookup(trimmed));
      }

      let userDoc: admin.firestore.QueryDocumentSnapshot | admin.firestore.DocumentSnapshot | null = null;

      if (docId.length > 0) {
        const docById = await db.collection('approved_users').doc(docId).get();
        if (docById.exists) {
          userDoc = docById;
        }
      }

      if (!userDoc) {
        for (const phoneHash of phoneHashes) {
          const hashedQuery = await db.collection('approved_users')
            .where('contactNumber_hash', '==', phoneHash)
            .limit(1)
            .get();
          if (!hashedQuery.empty) {
            userDoc = hashedQuery.docs[0];
            break;
          }
        }
      }

      if (!userDoc) {
        for (const candidate of phoneCandidates) {
          const trimmed = candidate.trim();
          if (trimmed.length === 0) {
            continue;
          }
          const plaintextQuery = await db.collection('approved_users')
            .where('contactNumber', '==', trimmed)
            .limit(1)
            .get();
          if (!plaintextQuery.empty) {
            userDoc = plaintextQuery.docs[0];
            break;
          }
        }
      }

      if (!userDoc || !userDoc.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          'User profile not found',
        );
      }

      const userData = userDoc.data() as Record<string, unknown>;
      const decryptedData = EncryptionHelper.decryptUserData(userData);
      const storedPhoneHash = typeof userData.contactNumber_hash === 'string'
        ? userData.contactNumber_hash
        : '';
      const storedContact = typeof decryptedData.contactNumber === 'string'
        ? decryptedData.contactNumber
        : (typeof userData.contactNumber === 'string' ? userData.contactNumber : '');

      const normalizedStoredContact = normalizePhone(storedContact);
      const ownershipVerified = (
        storedPhoneHash.length > 0 && phoneHashes.has(storedPhoneHash)
      ) || (
        normalizedStoredContact.length > 0 &&
        normalizedCandidateSet.has(normalizedStoredContact)
      );

      if (!ownershipVerified) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'Profile ownership verification failed',
        );
      }

      decryptedData['id'] = userDoc.id;
      const displayName = typeof decryptedData.fullName === 'string'
        ? decryptedData.fullName.trim()
        : '';
      if (displayName.length > 0) {
        decryptedData[DISPLAY_NAME_FIELD] = displayName;
      }

      return {
        success: true,
        userData: decryptedData,
      };
    } catch (error) {
      console.error('Get own decrypted profile error:', error);

      if (error instanceof functions.https.HttpsError) {
        throw error;
      }

      throw new functions.https.HttpsError(
        'internal',
        'Failed to load decrypted profile',
      );
    }
  });

/**
 * Cloud Function to get all users with decrypted data (for admin)
 */
export const getDecryptedUsers = functions
  .region('asia-east2')
  .https.onCall(async (data, context) => {
    try {
      const { collection: collectionName, adminId } = data as {
        collection: string;
        adminId: string;
      };

      // Verify admin exists
      const adminDoc = await db.collection('admins').doc(adminId).get();
      if (!adminDoc.exists) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'Admin not found'
        );
      }

      // Get all users from collection
      const snapshot = await db.collection(collectionName).get();
      
      const users = snapshot.docs.map((doc) => {
        const userData = doc.data() as Record<string, unknown>;
        const decryptedData = EncryptionHelper.decryptUserData(userData);
        decryptedData['id'] = doc.id;
        return decryptedData;
      });

      return { 
        success: true, 
        users 
      };
    } catch (error) {
      console.error('Get decrypted users error:', error);
      
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      
      throw new functions.https.HttpsError(
        'internal',
        'Failed to get users'
      );
    }
  });

/**
 * Cloud Function to migrate existing unencrypted user data to encrypted format
 * Run this once to encrypt existing data
 */
export const migrateToEncrypted = functions
  .region('asia-east2')
  .https.onCall(async (data, context) => {
    try {
      const { adminId } = data as { adminId: string };

      // Verify admin
      const adminDoc = await db.collection('admins').doc(adminId).get();
      if (!adminDoc.exists) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'Admin not found'
        );
      }

      const collections = ['approved_users', 'rejected_users'];
      let totalMigrated = 0;

      for (const collectionName of collections) {
        const snapshot = await db.collection(collectionName).get();
        
        for (const doc of snapshot.docs) {
          const userData = doc.data();
          const normalizedData = EncryptionHelper.normalizeLegacyUserData(userData);

          // Build only the missing/stale mirror encryption updates.
          const encryptionUpdates = EncryptionHelper.buildEncryptionFieldUpdates(
            normalizedData,
            userData,
          );
          const plaintextRestoreUpdates = EncryptionHelper.buildPlaintextFieldRestoreUpdates(
            normalizedData,
            userData,
          );

          const updates: Record<string, unknown> = {
            ...encryptionUpdates,
            ...plaintextRestoreUpdates,
          };
          const displayName = typeof normalizedData.fullName === 'string'
            ? normalizedData.fullName.trim()
            : '';
          if (displayName.length > 0) {
            updates[DISPLAY_NAME_FIELD] = displayName;
          } else if (Object.prototype.hasOwnProperty.call(userData, DISPLAY_NAME_FIELD)) {
            updates[DISPLAY_NAME_FIELD] = admin.firestore.FieldValue.delete();
          }

          if (Object.keys(updates).length === 0) {
            continue;
          }

          await doc.ref.set(updates, { merge: true });
          totalMigrated++;
        }
      }

      return { 
        success: true, 
        message: `Migrated ${totalMigrated} user records to encrypted format`
      };
    } catch (error) {
      console.error('Migration error:', error);
      throw new functions.https.HttpsError(
        'internal',
        'Migration failed'
      );
    }
  });

/**
 * One-time callable to convert existing pending_users docs to plaintext.
 * Keeps PII readable in pending queue and removes encryption mirror artifacts.
 */
export const migratePendingUsersToPlaintext = functions
  .region('asia-east2')
  .https.onCall(async (data, context) => {
    try {
      const { adminId } = data as { adminId: string };

      const adminDoc = await db.collection('admins').doc(adminId).get();
      if (!adminDoc.exists) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'Admin not found',
        );
      }

      const snapshot = await db.collection('pending_users').get();
      let totalUpdated = 0;

      for (const docSnap of snapshot.docs) {
        const currentData = docSnap.data() as Record<string, unknown>;
        const normalizedData = EncryptionHelper.normalizeLegacyUserData(currentData);
        const plaintextData = EncryptionHelper.stripEncryptionArtifacts(normalizedData);

        const normalizedPhone = typeof plaintextData.contactNumber === 'string'
          ? plaintextData.contactNumber.trim()
          : '';
        if (normalizedPhone.length > 0) {
          plaintextData.contactNumber = normalizedPhone;
          plaintextData.contactNumber_hash = EncryptionHelper.hashForLookup(normalizedPhone);
        } else {
          delete plaintextData.contactNumber_hash;
        }

        const displayName = typeof plaintextData.fullName === 'string'
          ? plaintextData.fullName.trim()
          : '';
        if (displayName.length > 0) {
          plaintextData[DISPLAY_NAME_FIELD] = displayName;
        } else {
          delete plaintextData[DISPLAY_NAME_FIELD];
        }

        plaintextData.status = 'pending';
        plaintextData.accountStatus = 'pending';

        await docSnap.ref.set(plaintextData, { merge: false });
        totalUpdated++;
      }

      return {
        success: true,
        message: `Converted ${totalUpdated} pending user records to plaintext format`,
      };
    } catch (error) {
      console.error('Pending plaintext migration error:', error);
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      throw new functions.https.HttpsError(
        'internal',
        'Pending plaintext migration failed',
      );
    }
  });

async function syncEncryptedMirrorsOnWrite(
  change: functions.Change<functions.firestore.DocumentSnapshot>,
): Promise<null> {
  if (!change.after.exists) {
    return null;
  }

  const afterData = (change.after.data() ?? {}) as Record<string, unknown>;
  const beforeData = change.before.exists
    ? (change.before.data() ?? {}) as Record<string, unknown>
    : undefined;
  const normalizedAfterData = EncryptionHelper.normalizeLegacyUserData(afterData);
  const encryptionUpdates = EncryptionHelper.buildEncryptionFieldUpdates(
    normalizedAfterData,
    beforeData,
  );
  const plaintextRestoreUpdates = EncryptionHelper.buildPlaintextFieldRestoreUpdates(
    normalizedAfterData,
    afterData,
  );
  const updates: Record<string, unknown> = {
    ...encryptionUpdates,
    ...plaintextRestoreUpdates,
  };
  const displayName = typeof normalizedAfterData.fullName === 'string'
    ? normalizedAfterData.fullName.trim()
    : '';
  const currentDisplayName = typeof afterData[DISPLAY_NAME_FIELD] === 'string'
    ? (afterData[DISPLAY_NAME_FIELD] as string).trim()
    : '';
  if (displayName.length > 0 && displayName !== currentDisplayName) {
    updates[DISPLAY_NAME_FIELD] = displayName;
  } else if (displayName.length === 0 && Object.prototype.hasOwnProperty.call(afterData, DISPLAY_NAME_FIELD)) {
    updates[DISPLAY_NAME_FIELD] = admin.firestore.FieldValue.delete();
  }

  if (Object.keys(updates).length === 0) {
    return null;
  }

  await change.after.ref.set(updates, { merge: true });
  return null;
}

export const syncPendingUsersEncryption = functions
  .region('asia-east2')
  .firestore.document('pending_users/{userId}')
  .onWrite(() => null);

export const syncApprovedUsersEncryption = functions
  .region('asia-east2')
  .firestore.document('approved_users/{userId}')
  .onWrite((change) => syncEncryptedMirrorsOnWrite(change));

export const syncRejectedUsersEncryption = functions
  .region('asia-east2')
  .firestore.document('rejected_users/{userId}')
  .onWrite((change) => syncEncryptedMirrorsOnWrite(change));

/**
 * Scheduled function that runs daily at midnight (Asia/Manila time)
 * Deletes reports older than 30 days from the database
 */
export const cleanupOldReports = functions
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

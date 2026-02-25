"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendPushOnApprovedUserBanUpdate = exports.sendPushOnResponderDeployment = exports.sendPushOnReportCreate = exports.sendPushOnAnnouncementCreate = exports.cleanupOldReports = exports.syncApprovedUsersEncryption = exports.deleteAnnouncementAsAdmin = exports.deleteReportAsAdmin = exports.getDecryptedUsers = exports.getOwnDecryptedProfile = exports.decryptUserData = exports.registerUserEncrypted = exports.migrateResponderRoleData = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");
admin.initializeApp();
const db = admin.firestore();
// PII fields that should have encrypted mirrors.
// `fullName` is intentionally plaintext-only (no encrypted mirror).
const ENCRYPTED_PII_FIELDS = [
    'email',
    'address',
    'dateOfBirth',
    'contactNumber',
    'password',
    'pin'
];
const LEGACY_DECRYPTABLE_FIELDS = ['fullName', ...ENCRYPTED_PII_FIELDS];
const PLAINTEXT_ONLY_FIELDS = new Set(['fullName']);
const ENCRYPTION_VERSION = 'aes-256-gcm-v2-compat';
const DISPLAY_NAME_FIELD = 'displayName';
const LOOKUP_HASH_FIELDS = new Set([
    'contactNumber',
    'pin',
]);
const NOTIFICATION_CHANNEL_ID = 'resq_notifications';
const ALERT_NOTIFICATION_CHANNEL_ID = 'resq_emergency_alerts';
const PUSH_TOPIC_ANNOUNCEMENTS = 'announcements';
const PUSH_TOPIC_REPORTS = 'reports';
const USER_TOKENS_COLLECTION = 'user_tokens';
const INVALID_FCM_TOKEN_ERROR_CODES = new Set([
    'messaging/invalid-registration-token',
    'messaging/registration-token-not-registered',
]);
function readTrimmedString(value) {
    if (typeof value !== 'string') {
        return '';
    }
    return value.trim();
}
function normalizeStatusValue(value) {
    return readTrimmedString(value)
        .toLowerCase()
        .replace(/[_-]+/g, ' ')
        .replace(/\s+/g, ' ');
}
function isDispatchStatus(value) {
    const normalized = normalizeStatusValue(value);
    return (normalized === 'responding' ||
        normalized === 'deployed' ||
        normalized === 'dispatched');
}
function hasResponderAssignment(data) {
    return (readTrimmedString(data.responderId).length > 0 ||
        readTrimmedString(data.responderContactNumber).length > 0 ||
        readTrimmedString(data.responderPhone).length > 0 ||
        readTrimmedString(data.responderName).length > 0);
}
function isResponderDeploymentTransition(beforeData, afterData) {
    var _a, _b, _c, _d, _e, _f;
    const afterAssigned = hasResponderAssignment(afterData);
    if (!afterAssigned) {
        return false;
    }
    const beforeAssigned = hasResponderAssignment(beforeData);
    const beforeStatus = (_a = beforeData.responderStatus) !== null && _a !== void 0 ? _a : beforeData.status;
    const afterStatus = (_b = afterData.responderStatus) !== null && _b !== void 0 ? _b : afterData.status;
    const beforeAssignedAt = (_d = (_c = beforeData.responderAssignedAt) !== null && _c !== void 0 ? _c : beforeData.deployedAt) !== null && _d !== void 0 ? _d : beforeData.respondingAt;
    const afterAssignedAt = (_f = (_e = afterData.responderAssignedAt) !== null && _e !== void 0 ? _e : afterData.deployedAt) !== null && _f !== void 0 ? _f : afterData.respondingAt;
    const assignedAtTransition = beforeAssignedAt == null && afterAssignedAt != null;
    const statusBecameDispatch = !isDispatchStatus(beforeStatus) && isDispatchStatus(afterStatus);
    return !beforeAssigned || assignedAtTransition || statusBecameDispatch;
}
function toFcmDataPayload(payload) {
    const data = {};
    for (const [key, value] of Object.entries(payload)) {
        if (value == null) {
            continue;
        }
        data[key] = String(value);
    }
    return data;
}
function normalizePhoneLikeValue(value) {
    return value.replace(/[^0-9]/g, '');
}
function normalizeAdminRole(value) {
    return readTrimmedString(value).toLowerCase();
}
async function assertAdminAccess(adminIdRaw) {
    var _a;
    const adminId = readTrimmedString(adminIdRaw);
    if (adminId.length === 0) {
        throw new functions.https.HttpsError('invalid-argument', 'adminId is required');
    }
    const adminDoc = await db.collection('admins').doc(adminId).get();
    if (!adminDoc.exists) {
        throw new functions.https.HttpsError('permission-denied', 'Admin not found');
    }
    const adminData = ((_a = adminDoc.data()) !== null && _a !== void 0 ? _a : {});
    if (normalizeAdminRole(adminData.role) !== 'admin') {
        throw new functions.https.HttpsError('permission-denied', 'Only admins can perform this action');
    }
    return adminId;
}
function normalizeRoleValueForMigration(value) {
    return readTrimmedString(value)
        .toLowerCase()
        .replace(/[_-]+/g, ' ')
        .replace(/\s+/g, ' ');
}
function isLegacyResponderRoleValue(value) {
    const normalized = normalizeRoleValueForMigration(value);
    return normalized === 'semi admin' || normalized === 'semiadmin';
}
const LEGACY_ROLE_QUERY_VALUES = [
    'semi-admin',
    'semi_admin',
    'semi admin',
    'semiadmin',
    'Semi Admin',
    'Semi-Admin',
];
/**
 * One-time admin migration:
 * - Moves docs from legacy `semi_admins` collection into `responders`
 * - Rewrites legacy role values (`semi-admin`, `semi_admin`, etc.) to `responder`
 */
exports.migrateResponderRoleData = functions
    .region('asia-east2')
    .https.onCall(async (data, context) => {
    var _a, _b;
    const payload = (data !== null && data !== void 0 ? data : {});
    const dryRun = payload.dryRun === true;
    await assertAdminAccess(payload.adminId);
    let scannedDocs = 0;
    let updatedRoleDocs = 0;
    let movedLegacyCollectionDocs = 0;
    let deletedLegacyCollectionDocs = 0;
    const commitBuffer = async (batch, ops) => {
        if (!dryRun && ops > 0) {
            await batch.commit();
        }
        return db.batch();
    };
    let batch = db.batch();
    let batchOps = 0;
    const flushIfNeeded = async (force = false) => {
        if (batchOps >= 420 || (force && batchOps > 0)) {
            batch = await commitBuffer(batch, batchOps);
            batchOps = 0;
        }
    };
    const legacySnapshot = await db.collection('semi_admins').get();
    scannedDocs += legacySnapshot.size;
    for (const doc of legacySnapshot.docs) {
        const docData = ((_a = doc.data()) !== null && _a !== void 0 ? _a : {});
        const responderRef = db.collection('responders').doc(doc.id);
        const nextData = Object.assign(Object.assign({}, docData), { role: 'responder' });
        movedLegacyCollectionDocs += 1;
        deletedLegacyCollectionDocs += 1;
        if (normalizeRoleValueForMigration(docData.role) !== 'responder') {
            updatedRoleDocs += 1;
        }
        if (!dryRun) {
            batch.set(responderRef, nextData, { merge: true });
            batch.delete(doc.ref);
            batchOps += 2;
            await flushIfNeeded();
        }
    }
    const collectionsToNormalize = [
        'responders',
        'approved_users',
        'pending_users',
        'users',
    ];
    for (const collectionName of collectionsToNormalize) {
        const snapshot = await db.collection(collectionName).get();
        scannedDocs += snapshot.size;
        for (const doc of snapshot.docs) {
            const docData = ((_b = doc.data()) !== null && _b !== void 0 ? _b : {});
            if (!isLegacyResponderRoleValue(docData.role)) {
                continue;
            }
            updatedRoleDocs += 1;
            if (!dryRun) {
                batch.set(doc.ref, { role: 'responder' }, { merge: true });
                batchOps += 1;
                await flushIfNeeded();
            }
        }
    }
    const legacyCommentSnapshot = await db
        .collectionGroup('comments')
        .where('role', 'in', LEGACY_ROLE_QUERY_VALUES)
        .get();
    scannedDocs += legacyCommentSnapshot.size;
    for (const doc of legacyCommentSnapshot.docs) {
        updatedRoleDocs += 1;
        if (!dryRun) {
            batch.set(doc.ref, { role: 'responder' }, { merge: true });
            batchOps += 1;
            await flushIfNeeded();
        }
    }
    await flushIfNeeded(true);
    const remainingLegacyRoles = {
        responders: 0,
        approved_users: 0,
        pending_users: 0,
        users: 0,
        comments: 0,
        legacyResponderCollection: 0,
    };
    for (const collectionName of collectionsToNormalize) {
        const remaining = await db
            .collection(collectionName)
            .where('role', 'in', LEGACY_ROLE_QUERY_VALUES)
            .limit(1)
            .get();
        remainingLegacyRoles[collectionName] =
            remaining.size;
    }
    const remainingLegacyComments = await db
        .collectionGroup('comments')
        .where('role', 'in', LEGACY_ROLE_QUERY_VALUES)
        .limit(1)
        .get();
    remainingLegacyRoles.comments = remainingLegacyComments.size;
    const remainingLegacyCollection = await db
        .collection('semi_admins')
        .limit(1)
        .get();
    remainingLegacyRoles.legacyResponderCollection = remainingLegacyCollection.size;
    return {
        success: true,
        dryRun,
        scannedDocs,
        updatedRoleDocs,
        movedLegacyCollectionDocs,
        deletedLegacyCollectionDocs,
        remainingLegacyRoles,
    };
});
function parseStorageTarget(rawValue) {
    const raw = readTrimmedString(rawValue);
    if (raw.length === 0) {
        return null;
    }
    if (raw.startsWith('gs://')) {
        const withoutScheme = raw.slice('gs://'.length);
        const firstSlash = withoutScheme.indexOf('/');
        if (firstSlash <= 0 || firstSlash >= withoutScheme.length - 1) {
            return null;
        }
        return {
            bucketName: withoutScheme.slice(0, firstSlash),
            objectPath: withoutScheme.slice(firstSlash + 1),
        };
    }
    if (raw.startsWith('https://') || raw.startsWith('http://')) {
        try {
            const parsedUrl = new URL(raw);
            const pathSegments = parsedUrl.pathname.split('/').filter(Boolean);
            const bucketSegmentIndex = pathSegments.indexOf('b');
            const objectSegmentIndex = pathSegments.indexOf('o');
            const encodedObjectPath = objectSegmentIndex >= 0 && objectSegmentIndex + 1 < pathSegments.length
                ? pathSegments.slice(objectSegmentIndex + 1).join('/')
                : '';
            if (encodedObjectPath.length === 0) {
                return null;
            }
            const bucketName = bucketSegmentIndex >= 0 && bucketSegmentIndex + 1 < pathSegments.length
                ? pathSegments[bucketSegmentIndex + 1]
                : undefined;
            return {
                bucketName,
                objectPath: decodeURIComponent(encodedObjectPath),
            };
        }
        catch (error) {
            console.error('Failed to parse storage URL:', raw, error);
            return null;
        }
    }
    return { objectPath: raw };
}
async function deleteStorageTarget(rawValue) {
    var _a;
    const target = parseStorageTarget(rawValue);
    if (!target) {
        return false;
    }
    try {
        const bucket = target.bucketName
            ? admin.storage().bucket(target.bucketName)
            : admin.storage().bucket();
        await bucket.file(target.objectPath).delete({ ignoreNotFound: true });
        return true;
    }
    catch (error) {
        console.error(`Failed deleting storage object ${target.objectPath} from ${(_a = target.bucketName) !== null && _a !== void 0 ? _a : '[default-bucket]'}:`, error);
        return false;
    }
}
async function deleteSubcollectionDocs(parentRef, subcollectionName) {
    let deletedDocs = 0;
    while (true) {
        const snapshot = await parentRef.collection(subcollectionName).limit(200).get();
        if (snapshot.empty) {
            break;
        }
        const batch = db.batch();
        for (const documentSnapshot of snapshot.docs) {
            batch.delete(documentSnapshot.ref);
            deletedDocs += 1;
        }
        await batch.commit();
    }
    return deletedDocs;
}
async function deleteReportCommentsAndReplies(reportRef) {
    let deletedDocs = 0;
    while (true) {
        const commentsSnapshot = await reportRef.collection('comments').limit(120).get();
        if (commentsSnapshot.empty) {
            break;
        }
        for (const commentSnapshot of commentsSnapshot.docs) {
            deletedDocs += await deleteSubcollectionDocs(commentSnapshot.ref, 'replies');
        }
        const batch = db.batch();
        for (const commentSnapshot of commentsSnapshot.docs) {
            batch.delete(commentSnapshot.ref);
            deletedDocs += 1;
        }
        await batch.commit();
    }
    return deletedDocs;
}
async function deleteVoteRecordsForReport(reportDocId, readableReportId) {
    const idsToDelete = new Set();
    const snapshots = [];
    const byDocId = await db
        .collection('voteRecords')
        .where('reportDocId', '==', reportDocId)
        .get();
    snapshots.push(byDocId);
    const normalizedReadableId = readableReportId.trim();
    if (normalizedReadableId.length > 0 && normalizedReadableId !== reportDocId) {
        const byReadableId = await db
            .collection('voteRecords')
            .where('reportId', '==', normalizedReadableId)
            .get();
        snapshots.push(byReadableId);
    }
    for (const snapshot of snapshots) {
        for (const docSnapshot of snapshot.docs) {
            idsToDelete.add(docSnapshot.id);
        }
    }
    if (idsToDelete.size === 0) {
        return 0;
    }
    let deletedDocs = 0;
    let batch = db.batch();
    let queuedDeletes = 0;
    for (const voteRecordId of idsToDelete) {
        batch.delete(db.collection('voteRecords').doc(voteRecordId));
        deletedDocs += 1;
        queuedDeletes += 1;
        if (queuedDeletes >= 400) {
            await batch.commit();
            batch = db.batch();
            queuedDeletes = 0;
        }
    }
    if (queuedDeletes > 0) {
        await batch.commit();
    }
    return deletedDocs;
}
function extractIncidentType(data) {
    return readTrimmedString(data.incidentType) || 'Incident';
}
function buildAnnouncementTitle(data) {
    return readTrimmedString(data.title) || 'New Announcement';
}
function buildAnnouncementBody(data) {
    const content = readTrimmedString(data.content);
    if (content.length > 0) {
        return content.length > 180 ? `${content.slice(0, 177)}...` : content;
    }
    return 'Tap to view the latest announcement.';
}
function buildReportTitle(data) {
    return `${extractIncidentType(data)} Reported`;
}
function buildReportBody(data) {
    const incidentType = extractIncidentType(data).toLowerCase();
    const barangay = readTrimmedString(data.barangay);
    if (barangay.length > 0) {
        return `A new ${incidentType} report was submitted in ${barangay}.`;
    }
    const details = readTrimmedString(data.details) || readTrimmedString(data.description);
    if (details.length > 0) {
        return details.length > 180 ? `${details.slice(0, 177)}...` : details;
    }
    return `A new ${incidentType} report was submitted.`;
}
function buildResponderDeploymentBody(data) {
    const incidentType = extractIncidentType(data).toLowerCase();
    const responderName = readTrimmedString(data.responderName);
    if (responderName.length > 0) {
        return `${responderName} is now responding to your ${incidentType} report.`;
    }
    return `A responder is now responding to your ${incidentType} report.`;
}
function buildResponderAssignmentTitle(data) {
    const incidentType = extractIncidentType(data);
    return `${incidentType} Deployment`;
}
function buildResponderAssignmentBody(data) {
    const incidentType = extractIncidentType(data).toLowerCase();
    const barangay = readTrimmedString(data.barangay);
    if (barangay.length > 0) {
        return `You were deployed to a ${incidentType} incident in ${barangay}.`;
    }
    return `You were deployed to a ${incidentType} incident.`;
}
function pushTokenCandidateVariants(candidates, seen, rawCandidate) {
    const pushCandidate = (candidate) => {
        const value = candidate.trim();
        if (value.length === 0 || seen.has(value)) {
            return;
        }
        seen.add(value);
        candidates.push(value);
    };
    const raw = readTrimmedString(rawCandidate);
    if (raw.length === 0) {
        return;
    }
    pushCandidate(raw);
    const digits = normalizePhoneLikeValue(raw);
    if (digits.length === 0) {
        return;
    }
    pushCandidate(digits);
    if (digits.startsWith('63')) {
        pushCandidate(`+${digits}`);
    }
}
function isBannedAccount(data) {
    return normalizeStatusValue(data.accountStatus) === 'banned';
}
function readBanReasons(data) {
    const rawReasons = data.banReasons;
    if (!Array.isArray(rawReasons)) {
        return [];
    }
    return rawReasons
        .map((reason) => readTrimmedString(reason))
        .filter((reason) => reason.length > 0);
}
function toTimestampMillis(value) {
    var _a, _b;
    if (value == null) {
        return null;
    }
    if (value instanceof admin.firestore.Timestamp) {
        return value.toMillis();
    }
    if (typeof value === 'object') {
        const maybeTimestamp = value;
        if (typeof maybeTimestamp.toMillis === 'function') {
            return maybeTimestamp.toMillis();
        }
        if (typeof maybeTimestamp.toDate === 'function') {
            return maybeTimestamp.toDate().getTime();
        }
        const seconds = (_a = value.seconds) !== null && _a !== void 0 ? _a : value._seconds;
        const nanos = (_b = value.nanoseconds) !== null && _b !== void 0 ? _b : value._nanoseconds;
        if (typeof seconds === 'number') {
            const msFromNanos = typeof nanos === 'number' ? nanos / 1000000 : 0;
            return Math.round((seconds * 1000) + msFromNanos);
        }
    }
    if (typeof value === 'number') {
        return Number.isFinite(value) ? value : null;
    }
    if (typeof value === 'string') {
        const parsed = Date.parse(value);
        return Number.isNaN(parsed) ? null : parsed;
    }
    return null;
}
function isPermanentBan(data) {
    if (!isBannedAccount(data)) {
        return false;
    }
    if (data.isPermanent === true) {
        return true;
    }
    const banType = normalizeStatusValue(data.banType);
    if (banType === 'permanent') {
        return true;
    }
    return data.bannedUntil == null;
}
function shouldSendBanUpdateNotification(beforeData, afterData) {
    const beforeBanned = isBannedAccount(beforeData);
    const afterBanned = isBannedAccount(afterData);
    if (!afterBanned) {
        return false;
    }
    if (!beforeBanned) {
        return true;
    }
    const beforeIsPermanent = isPermanentBan(beforeData);
    const afterIsPermanent = isPermanentBan(afterData);
    if (beforeIsPermanent !== afterIsPermanent) {
        return true;
    }
    const beforeUntil = toTimestampMillis(beforeData.bannedUntil);
    const afterUntil = toTimestampMillis(afterData.bannedUntil);
    if (beforeUntil !== afterUntil) {
        return true;
    }
    const beforeReasons = readBanReasons(beforeData).join('|');
    const afterReasons = readBanReasons(afterData).join('|');
    return beforeReasons !== afterReasons;
}
function formatBanUntilLabel(data) {
    const ms = toTimestampMillis(data.bannedUntil);
    if (ms == null) {
        return '';
    }
    const date = new Date(ms);
    if (Number.isNaN(date.getTime())) {
        return '';
    }
    return new Intl.DateTimeFormat('en-PH', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        hour12: true,
        timeZone: 'Asia/Manila',
    }).format(date);
}
function buildBanNotificationTitle(data) {
    return isPermanentBan(data)
        ? 'Account Permanently Banned'
        : 'Account Temporarily Banned';
}
function buildBanNotificationBody(data) {
    const reasons = readBanReasons(data);
    const reasonsText = reasons.length > 0 ? ` Reason: ${reasons.join(', ')}.` : '';
    if (isPermanentBan(data)) {
        return `Your RES-Q account was permanently banned.${reasonsText}`;
    }
    const untilLabel = formatBanUntilLabel(data);
    const untilText = untilLabel.length > 0 ? ` until ${untilLabel}` : '';
    return `Your RES-Q account was temporarily banned${untilText}.${reasonsText}`;
}
function buildReporterTokenDocCandidates(data) {
    const candidates = [];
    const seen = new Set();
    pushTokenCandidateVariants(candidates, seen, data.userId);
    pushTokenCandidateVariants(candidates, seen, data.contactNumber);
    return candidates;
}
function buildResponderTokenDocCandidates(data) {
    const candidates = [];
    const seen = new Set();
    pushTokenCandidateVariants(candidates, seen, data.responderId);
    pushTokenCandidateVariants(candidates, seen, data.responderContactNumber);
    pushTokenCandidateVariants(candidates, seen, data.responderPhone);
    return candidates;
}
function buildPhoneLookupVariants(rawValue) {
    const variants = [];
    const seen = new Set();
    const pushVariant = (value) => {
        const trimmed = value.trim();
        if (trimmed.length === 0 || seen.has(trimmed)) {
            return;
        }
        seen.add(trimmed);
        variants.push(trimmed);
    };
    const raw = readTrimmedString(rawValue);
    if (raw.length === 0) {
        return variants;
    }
    pushVariant(raw);
    const digits = normalizePhoneLikeValue(raw);
    if (digits.length === 0) {
        return variants;
    }
    pushVariant(digits);
    if (digits.startsWith('63')) {
        pushVariant(`+${digits}`);
        const local = digits.slice(2);
        if (local.length === 10) {
            pushVariant(local);
            pushVariant(`0${local}`);
        }
        return variants;
    }
    if (digits.length === 11 && digits.startsWith('0')) {
        const local = digits.slice(1);
        if (local.length === 10) {
            pushVariant(local);
            pushVariant(`63${local}`);
            pushVariant(`+63${local}`);
        }
        return variants;
    }
    if (digits.length === 10 && digits.startsWith('9')) {
        pushVariant(`0${digits}`);
        pushVariant(`63${digits}`);
        pushVariant(`+63${digits}`);
    }
    return variants;
}
function appendResponderTokenCandidatesFromProfileData(candidates, seen, profileId, profileData) {
    pushTokenCandidateVariants(candidates, seen, profileId);
    pushTokenCandidateVariants(candidates, seen, profileData.id);
    pushTokenCandidateVariants(candidates, seen, profileData.userId);
    pushTokenCandidateVariants(candidates, seen, profileData.uid);
    pushTokenCandidateVariants(candidates, seen, profileData.contactNumber);
    pushTokenCandidateVariants(candidates, seen, profileData.phoneNumber);
    pushTokenCandidateVariants(candidates, seen, profileData.responderContactNumber);
    pushTokenCandidateVariants(candidates, seen, profileData.responderPhone);
}
async function resolveResponderTokenRecord(reportId, data) {
    var _a, _b, _c, _d;
    const responderCollections = ['responders'];
    const candidates = buildResponderTokenDocCandidates(data);
    const seen = new Set(candidates);
    let tokenRecord = await getTokenRecordForCandidates(candidates);
    if (tokenRecord) {
        return tokenRecord;
    }
    const responderId = readTrimmedString(data.responderId);
    if (responderId.length > 0) {
        try {
            for (const collectionName of responderCollections) {
                const responderDoc = await db.collection(collectionName).doc(responderId).get();
                if (!responderDoc.exists) {
                    continue;
                }
                appendResponderTokenCandidatesFromProfileData(candidates, seen, responderDoc.id, ((_a = responderDoc.data()) !== null && _a !== void 0 ? _a : {}));
            }
            const approvedUserDoc = await db.collection('approved_users').doc(responderId).get();
            if (approvedUserDoc.exists) {
                appendResponderTokenCandidatesFromProfileData(candidates, seen, approvedUserDoc.id, ((_b = approvedUserDoc.data()) !== null && _b !== void 0 ? _b : {}));
            }
        }
        catch (error) {
            console.error(`Failed to load responder profile fallback docs for deployment push ${reportId}:`, error);
        }
    }
    tokenRecord = await getTokenRecordForCandidates(candidates);
    if (tokenRecord) {
        return tokenRecord;
    }
    const responderPhoneSeeds = [
        data.responderContactNumber,
        data.responderPhone,
    ];
    for (const seed of responderPhoneSeeds) {
        const phoneVariants = buildPhoneLookupVariants(seed);
        for (const phoneVariant of phoneVariants) {
            try {
                for (const collectionName of responderCollections) {
                    const responderContactMatch = await db
                        .collection(collectionName)
                        .where('contactNumber', '==', phoneVariant)
                        .limit(1)
                        .get();
                    if (!responderContactMatch.empty) {
                        const match = responderContactMatch.docs[0];
                        appendResponderTokenCandidatesFromProfileData(candidates, seen, match.id, ((_c = match.data()) !== null && _c !== void 0 ? _c : {}));
                    }
                    const responderPhoneMatch = await db
                        .collection(collectionName)
                        .where('phoneNumber', '==', phoneVariant)
                        .limit(1)
                        .get();
                    if (!responderPhoneMatch.empty) {
                        const match = responderPhoneMatch.docs[0];
                        appendResponderTokenCandidatesFromProfileData(candidates, seen, match.id, ((_d = match.data()) !== null && _d !== void 0 ? _d : {}));
                    }
                }
            }
            catch (error) {
                console.error(`Failed responder phone lookup fallback for deployment push ${reportId}:`, error);
            }
        }
    }
    tokenRecord = await getTokenRecordForCandidates(candidates);
    if (!tokenRecord) {
        console.warn(`Skipping responder assignment push for ${reportId}: no FCM token found after checking ${candidates.length} candidates.`);
    }
    return tokenRecord;
}
async function getTokenRecordForCandidates(candidates) {
    var _a;
    for (const candidate of candidates) {
        const doc = await db.collection(USER_TOKENS_COLLECTION).doc(candidate).get();
        if (!doc.exists) {
            continue;
        }
        const docData = ((_a = doc.data()) !== null && _a !== void 0 ? _a : {});
        const token = readTrimmedString(docData.fcmToken);
        if (token.length > 0) {
            return {
                docId: doc.id,
                fcmToken: token,
            };
        }
    }
    return null;
}
async function deleteTokenRecord(docId) {
    try {
        await db.collection(USER_TOKENS_COLLECTION).doc(docId).delete();
    }
    catch (error) {
        console.error(`Failed to delete stale token doc ${docId}:`, error);
    }
}
async function sendTopicPushNotification(topic, title, body, data) {
    const message = {
        topic,
        notification: { title, body },
        data: toFcmDataPayload(data),
        android: {
            priority: 'high',
            notification: {
                channelId: NOTIFICATION_CHANNEL_ID,
                sound: 'default',
            },
        },
        apns: {
            headers: {
                'apns-priority': '10',
                'apns-push-type': 'alert',
            },
            payload: {
                aps: {
                    sound: 'default',
                },
            },
        },
    };
    const messageId = await admin.messaging().send(message);
    console.log(`Sent topic push notification (${topic}): ${messageId}`);
}
async function sendUserTokenPushNotification(docId, fcmToken, title, body, data, options) {
    var _a;
    const channelId = readTrimmedString(options === null || options === void 0 ? void 0 : options.channelId) || NOTIFICATION_CHANNEL_ID;
    const message = {
        token: fcmToken,
        notification: { title, body },
        data: toFcmDataPayload(data),
        android: {
            priority: 'high',
            notification: {
                channelId,
                sound: 'default',
            },
        },
        apns: {
            headers: {
                'apns-priority': '10',
                'apns-push-type': 'alert',
            },
            payload: {
                aps: {
                    sound: 'default',
                },
            },
        },
    };
    try {
        const messageId = await admin.messaging().send(message);
        console.log(`Sent device push notification (${docId}): ${messageId}`);
    }
    catch (error) {
        const errorCode = (_a = error.code) !== null && _a !== void 0 ? _a : '';
        if (INVALID_FCM_TOKEN_ERROR_CODES.has(errorCode)) {
            await deleteTokenRecord(docId);
            console.warn(`Deleted stale token for ${docId} due to ${errorCode}`);
            return;
        }
        throw error;
    }
}
/**
 * AES-256-GCM Encryption using Node.js crypto
 */
class EncryptionHelper {
    static isNonEmptyString(value) {
        return typeof value === 'string' && value.trim().length > 0;
    }
    static cipherField(field) {
        return `${field}${this.CIPHER_SUFFIX}`;
    }
    static hashField(field) {
        return `${field}${this.HASH_SUFFIX}`;
    }
    static hashValue(value) {
        return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
    }
    static shouldPersistHash(field) {
        return LOOKUP_HASH_FIELDS.has(field);
    }
    static looksLikeCiphertext(value) {
        const trimmed = value.trim();
        if (trimmed.length < 40) {
            return false;
        }
        // AES-GCM payloads are stored as base64 (IV + authTag + ciphertext)
        return /^[A-Za-z0-9+/=]+$/.test(trimmed) && !trimmed.includes(' ');
    }
    static hashForLookup(value) {
        return this.hashValue(value);
    }
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
        for (const field of ENCRYPTED_PII_FIELDS) {
            const value = encrypted[field];
            const cipherField = this.cipherField(field);
            const hashField = this.hashField(field);
            const encryptedFlagField = `${field}_encrypted`;
            if (this.isNonEmptyString(value)) {
                // Compatibility mode:
                // Keep plaintext fields for existing mobile/web query flows,
                // while storing AES-256-GCM encrypted mirrors for defense/security proof.
                encrypted[cipherField] = this.encrypt(value);
                if (this.shouldPersistHash(field)) {
                    encrypted[hashField] = this.hashValue(value);
                }
                else {
                    delete encrypted[hashField];
                }
                delete encrypted[encryptedFlagField];
            }
            else {
                delete encrypted[cipherField];
                delete encrypted[hashField];
                delete encrypted[encryptedFlagField];
            }
        }
        // Keep selected fields plaintext-only by removing any legacy encryption artifacts.
        for (const field of PLAINTEXT_ONLY_FIELDS) {
            delete encrypted[this.cipherField(field)];
            delete encrypted[this.hashField(field)];
            delete encrypted[`${field}_encrypted`];
        }
        encrypted['_encryptedAt'] = admin.firestore.FieldValue.serverTimestamp();
        encrypted['_encryptionVersion'] = ENCRYPTION_VERSION;
        return encrypted;
    }
    static normalizeLegacyUserData(userData) {
        const normalized = Object.assign({}, userData);
        for (const field of LEGACY_DECRYPTABLE_FIELDS) {
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
            if (hasTopLevelField &&
                topLevelLooksCiphertext &&
                this.isNonEmptyString(mirroredCipherValue)) {
                try {
                    normalized[field] = this.decrypt(mirroredCipherValue);
                    continue;
                }
                catch (error) {
                    console.error(`Failed to decrypt mirrored field ${field}:`, error);
                }
            }
            // Backward compatibility for legacy v1 format where the top-level field
            // itself may contain ciphertext and <field>_encrypted is true.
            if (normalized[encryptedFlagField] &&
                hasTopLevelString &&
                topLevelLooksCiphertext) {
                try {
                    normalized[field] = this.decrypt(normalized[field]);
                }
                catch (_a) {
                    // Keep original value if it was already plaintext.
                }
            }
        }
        return normalized;
    }
    static buildEncryptionFieldUpdates(afterData, beforeData) {
        const updates = {};
        let hasChanges = false;
        for (const field of ENCRYPTED_PII_FIELDS) {
            const value = afterData[field];
            let beforeValue = beforeData === null || beforeData === void 0 ? void 0 : beforeData[field];
            const cipherField = this.cipherField(field);
            const hashField = this.hashField(field);
            const encryptedFlagField = `${field}_encrypted`;
            if (!this.isNonEmptyString(beforeValue) && beforeData && this.isNonEmptyString(beforeData[cipherField])) {
                try {
                    beforeValue = this.decrypt(beforeData[cipherField]);
                }
                catch (_a) {
                    // Ignore and keep fallback comparison value.
                }
            }
            if (this.isNonEmptyString(value)) {
                const shouldPersistHash = this.shouldPersistHash(field);
                const plaintextHash = shouldPersistHash ? this.hashValue(value) : '';
                const storedHash = typeof afterData[hashField] === 'string'
                    ? afterData[hashField]
                    : '';
                const hasCipher = this.isNonEmptyString(afterData[cipherField]);
                const hasEncryptedFlag = afterData[encryptedFlagField] != null;
                const plaintextChanged = beforeData
                    ? value !== beforeValue
                    : false;
                if (plaintextChanged || !hasCipher || (shouldPersistHash && storedHash !== plaintextHash)) {
                    updates[cipherField] = this.encrypt(value);
                    if (shouldPersistHash) {
                        updates[hashField] = plaintextHash;
                    }
                    else if (afterData[hashField] != null) {
                        updates[hashField] = admin.firestore.FieldValue.delete();
                    }
                    if (hasEncryptedFlag) {
                        updates[encryptedFlagField] = admin.firestore.FieldValue.delete();
                    }
                    hasChanges = true;
                }
                else {
                    if (!shouldPersistHash && afterData[hashField] != null) {
                        updates[hashField] = admin.firestore.FieldValue.delete();
                        hasChanges = true;
                    }
                    if (hasEncryptedFlag) {
                        updates[encryptedFlagField] = admin.firestore.FieldValue.delete();
                        hasChanges = true;
                    }
                }
            }
            else {
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
        // Remove legacy artifacts for fields that are now plaintext-only.
        for (const field of PLAINTEXT_ONLY_FIELDS) {
            const cipherField = this.cipherField(field);
            const hashField = this.hashField(field);
            const encryptedFlagField = `${field}_encrypted`;
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
        if (hasChanges) {
            updates['_encryptedAt'] = admin.firestore.FieldValue.serverTimestamp();
            updates['_encryptionVersion'] = ENCRYPTION_VERSION;
        }
        return updates;
    }
    static buildPlaintextFieldRestoreUpdates(normalizedData, currentData) {
        const updates = {};
        for (const field of LEGACY_DECRYPTABLE_FIELDS) {
            const normalizedValue = normalizedData[field];
            const currentValue = currentData[field];
            if (this.isNonEmptyString(normalizedValue) && currentValue !== normalizedValue) {
                updates[field] = normalizedValue;
            }
        }
        return updates;
    }
    static buildEncryptionArtifactDeleteUpdates() {
        const updates = {};
        for (const field of LEGACY_DECRYPTABLE_FIELDS) {
            updates[this.cipherField(field)] = admin.firestore.FieldValue.delete();
            updates[this.hashField(field)] = admin.firestore.FieldValue.delete();
            updates[`${field}_encrypted`] = admin.firestore.FieldValue.delete();
        }
        updates['_encryptedAt'] = admin.firestore.FieldValue.delete();
        updates['_encryptionVersion'] = admin.firestore.FieldValue.delete();
        return updates;
    }
    static decryptUserData(userData) {
        const decrypted = Object.assign({}, userData);
        for (const field of LEGACY_DECRYPTABLE_FIELDS) {
            const cipherField = this.cipherField(field);
            const topLevelValue = decrypted[field];
            const hasTopLevelString = this.isNonEmptyString(topLevelValue);
            // If top-level value is already readable plaintext, trust it.
            if (hasTopLevelString && !this.looksLikeCiphertext(topLevelValue)) {
                continue;
            }
            if (this.isNonEmptyString(decrypted[cipherField])) {
                try {
                    decrypted[field] = this.decrypt(decrypted[cipherField]);
                    continue;
                }
                catch (error) {
                    console.error(`Failed to decrypt mirrored field ${field}:`, error);
                    decrypted[field] = '[Decryption Failed]';
                    continue;
                }
            }
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
EncryptionHelper.CIPHER_SUFFIX = '_cipher';
EncryptionHelper.HASH_SUFFIX = '_hash';
/**
 * Cloud Function to register a new user in pending_users.
 * Pending accounts are stored as plaintext for admin review.
 * Encryption is enforced once the account is moved to approved_users.
 */
exports.registerUserEncrypted = functions
    .region('asia-east2')
    .https.onCall(async (data, context) => {
    try {
        const payload = Object.assign({}, data);
        // Validate required fields
        const contactNumberRaw = payload.contactNumber;
        if (!contactNumberRaw || typeof contactNumberRaw !== 'string') {
            throw new functions.https.HttpsError('invalid-argument', 'Contact number is required');
        }
        const phoneNumber = contactNumberRaw.trim();
        if (!phoneNumber) {
            throw new functions.https.HttpsError('invalid-argument', 'Contact number is required');
        }
        const emailRaw = payload.email;
        if (!emailRaw || typeof emailRaw !== 'string') {
            throw new functions.https.HttpsError('invalid-argument', 'Email is required');
        }
        const normalizedEmail = emailRaw.trim().toLowerCase();
        const emailPattern = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
        if (!emailPattern.test(normalizedEmail)) {
            throw new functions.https.HttpsError('invalid-argument', 'A valid email is required');
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
        const pendingIds = new Set();
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
            throw new functions.https.HttpsError('already-exists', 'This phone number is already registered');
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
            throw new functions.https.HttpsError('already-exists', 'This phone number is already registered');
        }
        const pendingEmailQueries = await Promise.all([
            db.collection('pending_users')
                .where('emailLower', '==', normalizedEmail)
                .limit(1)
                .get(),
            db.collection('pending_users')
                .where('email', '==', normalizedEmail)
                .limit(1)
                .get(),
        ]);
        if (pendingEmailQueries.some((querySnapshot) => !querySnapshot.empty)) {
            throw new functions.https.HttpsError('already-exists', 'This email is already registered');
        }
        const approvedEmailQueries = await Promise.all([
            db.collection('approved_users')
                .where('emailLower', '==', normalizedEmail)
                .limit(1)
                .get(),
            db.collection('approved_users')
                .where('email', '==', normalizedEmail)
                .limit(1)
                .get(),
        ]);
        if (approvedEmailQueries.some((querySnapshot) => !querySnapshot.empty)) {
            throw new functions.https.HttpsError('already-exists', 'This email is already registered');
        }
        // Normalize user payload and keep plaintext in pending_users.
        const normalizedUserData = EncryptionHelper.normalizeLegacyUserData(payload);
        normalizedUserData.contactNumber = phoneNumber;
        normalizedUserData.email = normalizedEmail;
        normalizedUserData.emailLower = normalizedEmail;
        const pendingUserData = Object.assign({}, normalizedUserData);
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
        const pendingWritePayload = Object.assign(Object.assign({}, cleanupEncryptionArtifacts), pendingUserData);
        // Store in pending_users collection
        let userId;
        if (uid) {
            await db.collection('pending_users').doc(uid).set(pendingWritePayload, { merge: true });
            userId = uid;
        }
        else {
            const docRef = await db.collection('pending_users').add(pendingWritePayload);
            userId = docRef.id;
        }
        console.log(`User registered in pending_users (plaintext pending flow): ${userId}`);
        return {
            success: true,
            userId,
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
 * Cloud Function for end-users to fetch their own decrypted profile data.
 * Uses contact-number ownership checks to work with the app's phone-first auth flow.
 */
exports.getOwnDecryptedProfile = functions
    .region('asia-east2')
    .https.onCall(async (data, context) => {
    try {
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', 'Authentication is required');
        }
        const payload = (data !== null && data !== void 0 ? data : {});
        const contactNumber = typeof payload.contactNumber === 'string'
            ? payload.contactNumber.trim()
            : '';
        const docId = typeof payload.docId === 'string'
            ? payload.docId.trim()
            : '';
        if (contactNumber.length === 0) {
            throw new functions.https.HttpsError('invalid-argument', 'contactNumber is required');
        }
        const normalizePhone = (value) => value.replace(/[^0-9]/g, '');
        const normalizedContactNumber = normalizePhone(contactNumber);
        if (normalizedContactNumber.length === 0) {
            throw new functions.https.HttpsError('invalid-argument', 'contactNumber is invalid');
        }
        const phoneCandidates = new Set();
        phoneCandidates.add(contactNumber);
        phoneCandidates.add(normalizedContactNumber);
        if (normalizedContactNumber.startsWith('63')) {
            phoneCandidates.add(`+${normalizedContactNumber}`);
            if (normalizedContactNumber.length === 12) {
                phoneCandidates.add(`0${normalizedContactNumber.substring(2)}`);
            }
        }
        else if (normalizedContactNumber.length === 10) {
            phoneCandidates.add(`+63${normalizedContactNumber}`);
            phoneCandidates.add(`0${normalizedContactNumber}`);
        }
        else if (normalizedContactNumber.startsWith('0') &&
            normalizedContactNumber.length === 11) {
            const local = normalizedContactNumber.substring(1);
            phoneCandidates.add(`+63${local}`);
            phoneCandidates.add(`63${local}`);
        }
        const normalizedCandidateSet = new Set();
        const phoneHashes = new Set();
        for (const candidate of phoneCandidates) {
            const trimmed = candidate.trim();
            if (trimmed.length === 0) {
                continue;
            }
            normalizedCandidateSet.add(normalizePhone(trimmed));
            phoneHashes.add(EncryptionHelper.hashForLookup(trimmed));
        }
        let userDoc = null;
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
            throw new functions.https.HttpsError('not-found', 'User profile not found');
        }
        const userData = userDoc.data();
        const decryptedData = EncryptionHelper.decryptUserData(userData);
        const storedPhoneHash = typeof userData.contactNumber_hash === 'string'
            ? userData.contactNumber_hash
            : '';
        const storedContact = typeof decryptedData.contactNumber === 'string'
            ? decryptedData.contactNumber
            : (typeof userData.contactNumber === 'string' ? userData.contactNumber : '');
        const normalizedStoredContact = normalizePhone(storedContact);
        const ownershipVerified = (storedPhoneHash.length > 0 && phoneHashes.has(storedPhoneHash)) || (normalizedStoredContact.length > 0 &&
            normalizedCandidateSet.has(normalizedStoredContact));
        if (!ownershipVerified) {
            throw new functions.https.HttpsError('permission-denied', 'Profile ownership verification failed');
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
    }
    catch (error) {
        console.error('Get own decrypted profile error:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', 'Failed to load decrypted profile');
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
 * Admin-only hard delete for a report document.
 * Also removes report comments/replies, linked vote records, and media in Storage.
 */
exports.deleteReportAsAdmin = functions
    .region('asia-east2')
    .https.onCall(async (data, context) => {
    var _a, _b;
    try {
        const payload = (data !== null && data !== void 0 ? data : {});
        const reportId = readTrimmedString(payload.reportId);
        await assertAdminAccess(payload.adminId);
        if (reportId.length === 0) {
            throw new functions.https.HttpsError('invalid-argument', 'reportId is required');
        }
        const reportRef = db.collection('reports').doc(reportId);
        const reportSnapshot = await reportRef.get();
        if (!reportSnapshot.exists) {
            throw new functions.https.HttpsError('not-found', 'Report not found');
        }
        const reportData = ((_a = reportSnapshot.data()) !== null && _a !== void 0 ? _a : {});
        const mediaDeleted = await deleteStorageTarget((_b = reportData.mediaUrl) !== null && _b !== void 0 ? _b : reportData.imageUrl);
        const deletedCommentDocs = await deleteReportCommentsAndReplies(reportRef);
        const deletedVoteRecordDocs = await deleteVoteRecordsForReport(reportId, readTrimmedString(reportData.reportId));
        await reportRef.delete();
        return {
            success: true,
            reportId,
            mediaDeleted,
            deletedCommentDocs,
            deletedVoteRecordDocs,
        };
    }
    catch (error) {
        console.error('deleteReportAsAdmin failed:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', 'Failed to delete report');
    }
});
/**
 * Admin-only hard delete for an announcement document and its optional image.
 */
exports.deleteAnnouncementAsAdmin = functions
    .region('asia-east2')
    .https.onCall(async (data, context) => {
    var _a;
    try {
        const payload = (data !== null && data !== void 0 ? data : {});
        const announcementId = readTrimmedString(payload.announcementId);
        await assertAdminAccess(payload.adminId);
        if (announcementId.length === 0) {
            throw new functions.https.HttpsError('invalid-argument', 'announcementId is required');
        }
        const announcementRef = db.collection('announcements').doc(announcementId);
        const announcementSnapshot = await announcementRef.get();
        if (!announcementSnapshot.exists) {
            throw new functions.https.HttpsError('not-found', 'Announcement not found');
        }
        const announcementData = ((_a = announcementSnapshot.data()) !== null && _a !== void 0 ? _a : {});
        const mediaDeleted = await deleteStorageTarget(announcementData.imageUrl);
        await announcementRef.delete();
        return {
            success: true,
            announcementId,
            mediaDeleted,
        };
    }
    catch (error) {
        console.error('deleteAnnouncementAsAdmin failed:', error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', 'Failed to delete announcement');
    }
});
async function syncEncryptedMirrorsOnWrite(change) {
    var _a, _b;
    if (!change.after.exists) {
        return null;
    }
    const afterData = ((_a = change.after.data()) !== null && _a !== void 0 ? _a : {});
    const beforeData = change.before.exists
        ? ((_b = change.before.data()) !== null && _b !== void 0 ? _b : {})
        : undefined;
    const normalizedAfterData = EncryptionHelper.normalizeLegacyUserData(afterData);
    const encryptionUpdates = EncryptionHelper.buildEncryptionFieldUpdates(normalizedAfterData, beforeData);
    const plaintextRestoreUpdates = EncryptionHelper.buildPlaintextFieldRestoreUpdates(normalizedAfterData, afterData);
    const updates = Object.assign(Object.assign({}, encryptionUpdates), plaintextRestoreUpdates);
    const displayName = typeof normalizedAfterData.fullName === 'string'
        ? normalizedAfterData.fullName.trim()
        : '';
    const currentDisplayName = typeof afterData[DISPLAY_NAME_FIELD] === 'string'
        ? afterData[DISPLAY_NAME_FIELD].trim()
        : '';
    if (displayName.length > 0 && displayName !== currentDisplayName) {
        updates[DISPLAY_NAME_FIELD] = displayName;
    }
    else if (displayName.length === 0 && Object.prototype.hasOwnProperty.call(afterData, DISPLAY_NAME_FIELD)) {
        updates[DISPLAY_NAME_FIELD] = admin.firestore.FieldValue.delete();
    }
    if (Object.keys(updates).length === 0) {
        return null;
    }
    await change.after.ref.set(updates, { merge: true });
    return null;
}
exports.syncApprovedUsersEncryption = functions
    .region('asia-east2')
    .firestore.document('approved_users/{userId}')
    .onWrite((change) => syncEncryptedMirrorsOnWrite(change));
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
/**
 * Broadcasts push notifications to all subscribed devices when an announcement is published.
 */
exports.sendPushOnAnnouncementCreate = functions
    .region('asia-east2')
    .firestore.document('announcements/{announcementId}')
    .onCreate(async (snapshot, context) => {
    var _a;
    const data = ((_a = snapshot.data()) !== null && _a !== void 0 ? _a : {});
    if (data.isPlaceholder === true) {
        return null;
    }
    const announcementId = context.params.announcementId;
    const title = buildAnnouncementTitle(data);
    const body = buildAnnouncementBody(data);
    await sendTopicPushNotification(PUSH_TOPIC_ANNOUNCEMENTS, title, body, {
        type: 'announcement',
        announcementId,
    });
    return null;
});
/**
 * Broadcasts push notifications to all subscribed devices whenever a report is submitted.
 */
exports.sendPushOnReportCreate = functions
    .region('asia-east2')
    .firestore.document('reports/{reportId}')
    .onCreate(async (snapshot, context) => {
    var _a;
    const data = ((_a = snapshot.data()) !== null && _a !== void 0 ? _a : {});
    const reportId = context.params.reportId;
    const title = buildReportTitle(data);
    const body = buildReportBody(data);
    await sendTopicPushNotification(PUSH_TOPIC_REPORTS, title, body, {
        type: 'report',
        reportId,
        incidentType: extractIncidentType(data),
    });
    return null;
});
/**
 * Sends direct push notifications when a responder is deployed:
 * - report owner receives "Responder Deployed"
 * - assigned responder receives an emergency deployment alert
 */
exports.sendPushOnResponderDeployment = functions
    .region('asia-east2')
    .firestore.document('reports/{reportId}')
    .onUpdate(async (change, context) => {
    var _a, _b;
    const beforeData = ((_a = change.before.data()) !== null && _a !== void 0 ? _a : {});
    const afterData = ((_b = change.after.data()) !== null && _b !== void 0 ? _b : {});
    if (!isResponderDeploymentTransition(beforeData, afterData)) {
        return null;
    }
    const reportId = context.params.reportId;
    const incidentType = extractIncidentType(afterData);
    const responderName = readTrimmedString(afterData.responderName);
    const reporterTokenDocCandidates = buildReporterTokenDocCandidates(afterData);
    if (reporterTokenDocCandidates.length === 0) {
        console.warn(`Skipping report-owner deployment push for ${reportId}: no user token candidates.`);
    }
    else {
        const reporterTokenRecord = await getTokenRecordForCandidates(reporterTokenDocCandidates);
        if (!reporterTokenRecord) {
            console.warn(`Skipping report-owner deployment push for ${reportId}: no FCM token found.`);
        }
        else {
            await sendUserTokenPushNotification(reporterTokenRecord.docId, reporterTokenRecord.fcmToken, 'Responder Deployed', buildResponderDeploymentBody(afterData), {
                type: 'responder_deployed',
                reportId,
                incidentType,
                responderName,
            });
        }
    }
    const responderTokenRecord = await resolveResponderTokenRecord(reportId, afterData);
    if (!responderTokenRecord) {
        return null;
    }
    await sendUserTokenPushNotification(responderTokenRecord.docId, responderTokenRecord.fcmToken, buildResponderAssignmentTitle(afterData), buildResponderAssignmentBody(afterData), {
        type: 'responder_assignment',
        reportId,
        incidentType,
        responderName,
    }, {
        channelId: ALERT_NOTIFICATION_CHANNEL_ID,
    });
    return null;
});
/**
 * Sends a direct push notification when an approved user becomes banned.
 * Covers both temporary and permanent bans and includes admin-selected reasons.
 */
exports.sendPushOnApprovedUserBanUpdate = functions
    .region('asia-east2')
    .firestore.document('approved_users/{userId}')
    .onUpdate(async (change, context) => {
    var _a, _b;
    const beforeData = ((_a = change.before.data()) !== null && _a !== void 0 ? _a : {});
    const afterData = ((_b = change.after.data()) !== null && _b !== void 0 ? _b : {});
    if (!shouldSendBanUpdateNotification(beforeData, afterData)) {
        return null;
    }
    const userId = readTrimmedString(context.params.userId);
    const tokenDocCandidates = buildReporterTokenDocCandidates(Object.assign(Object.assign({}, afterData), { userId }));
    if (tokenDocCandidates.length === 0) {
        console.warn(`Skipping account ban push for ${userId}: no user token candidates.`);
        return null;
    }
    const tokenRecord = await getTokenRecordForCandidates(tokenDocCandidates);
    if (!tokenRecord) {
        console.warn(`Skipping account ban push for ${userId}: no FCM token found.`);
        return null;
    }
    const isPermanent = isPermanentBan(afterData);
    const title = buildBanNotificationTitle(afterData);
    const body = buildBanNotificationBody(afterData);
    const reasons = readBanReasons(afterData);
    const bannedUntilMillis = toTimestampMillis(afterData.bannedUntil);
    const pushData = {
        type: 'account_ban',
        banType: isPermanent ? 'permanent' : 'temporary',
        banReasons: reasons.join('|'),
    };
    if (bannedUntilMillis != null) {
        pushData.bannedUntil = new Date(bannedUntilMillis).toISOString();
    }
    await sendUserTokenPushNotification(tokenRecord.docId, tokenRecord.fcmToken, title, body, pushData);
    try {
        await db
            .collection('users')
            .doc(tokenRecord.docId)
            .collection('notifications')
            .add(Object.assign({ title,
            body, type: 'account_ban', banType: isPermanent ? 'permanent' : 'temporary', reasons, read: false, createdAt: admin.firestore.FieldValue.serverTimestamp() }, (bannedUntilMillis == null
            ? {}
            : {
                bannedUntil: admin.firestore.Timestamp.fromMillis(bannedUntilMillis),
            })));
    }
    catch (error) {
        console.error(`Failed to store account ban notification feed item for ${tokenRecord.docId}:`, error);
    }
    return null;
});
//# sourceMappingURL=index.js.map
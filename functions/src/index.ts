import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();

const db = admin.firestore();

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

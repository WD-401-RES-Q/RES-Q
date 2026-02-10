const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onObjectFinalized} = require("firebase-functions/v2/storage");
const {initializeApp} = require("firebase-admin/app");
const {getMessaging} = require("firebase-admin/messaging");
const {getFirestore} = require("firebase-admin/firestore");
const {getStorage, getDownloadURL} = require("firebase-admin/storage");
const sharp = require("sharp");
const path = require("path");
const os = require("os");
const fs = require("fs/promises");
const crypto = require("crypto");

initializeApp();

/**
 * Send push notification when a new announcement is created
 * Sends to all users subscribed to the 'announcements' topic
 */
exports.onAnnouncementCreated = onDocumentCreated(
    {
      document: "announcements/{announcementId}",
      region: "asia-southeast1",
    },
    async (event) => {
      const announcement = event.data.data();

      // Skip if this is a placeholder announcement
      if (announcement.isPlaceholder === true) {
        console.log("Skipping placeholder announcement");
        return null;
      }

      const title = announcement.title || "New Announcement";
      const content = announcement.content || "Check the app for details";

      // Prepare the notification message
      const message = {
        notification: {
          title: title,
          body: content,
        },
        data: {
          type: "announcement",
          announcementId: event.params.announcementId,
          title: title,
          content: content,
        },
        topic: "announcements",
        android: {
          priority: "high",
          notification: {
            channelId: "resq_notifications",
            color: "#AC1B22",
            icon: "ic_launcher",
            sound: "default",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      };

      try {
        const response = await getMessaging().send(message);
        console.log("Successfully sent announcement notification:", response);
        return response;
      } catch (error) {
        console.error("Error sending announcement notification:", error);
        return null;
      }
    });

/**
 * Send push notification when a new incident report is created
 * Sends to all users by getting their FCM tokens from user_tokens collection
 */
exports.onReportCreated = onDocumentCreated(
    {
      document: "reports/{reportId}",
      region: "asia-southeast1",
    },
    async (event) => {
      const report = event.data.data();

      // Skip if location data is missing
      if (!report.location || report.latitude == null ||
          report.longitude == null) {
        console.log("Skipping report without location data");
        return null;
      }

      const incidentType = report.incidentType || "Incident";
      const barangay = report.barangay || "your area";
      const details = report.details || "";

      // Prepare the notification message
      const notificationTitle = `${incidentType} Reported`;
      const notificationBody = `A ${incidentType.toLowerCase()} has been ` +
                              `reported in ${barangay}`;

      // Get all user tokens from the user_tokens collection
      const db = getFirestore();
      const tokensSnapshot = await db.collection("user_tokens").get();

      if (tokensSnapshot.empty) {
        console.log("No user tokens found");
        return null;
      }

      // Collect all valid FCM tokens
      const tokens = [];
      tokensSnapshot.forEach((doc) => {
        const data = doc.data();
        if (data.fcmToken) {
          tokens.push(data.fcmToken);
        }
      });

      if (tokens.length === 0) {
        console.log("No valid FCM tokens found");
        return null;
      }

      // Prepare multicast message
      const message = {
        notification: {
          title: notificationTitle,
          body: notificationBody,
        },
        data: {
          type: "new_report",
          reportId: event.params.reportId,
          incidentType: incidentType,
          barangay: barangay,
          latitude: report.latitude.toString(),
          longitude: report.longitude.toString(),
        },
        android: {
          priority: "high",
          notification: {
            channelId: "resq_notifications",
            color: "#AC1B22",
            icon: "ic_launcher",
            sound: "default",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
        tokens: tokens,
      };

      try {
        const response = await getMessaging().sendEachForMulticast(message);
        console.log(`Successfully sent report notification to ${response.successCount} devices`);

        // Log failures
        if (response.failureCount > 0) {
          console.log(`Failed to send to ${response.failureCount} devices`);
          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              console.error(`Error sending to token ${tokens[idx]}:`, resp.error);
            }
          });
        }

        return response;
      } catch (error) {
        console.error("Error sending report notification:", error);
        return null;
      }
    });

/**
 * Generate report image derivatives (thumbnail webp/jpg) and store references
 * back in the corresponding report document for lightweight list rendering.
 */
exports.onReportImageUploaded = onObjectFinalized(
    {
      region: "asia-southeast1",
      bucket: "res-q-93ca6.firebasestorage.app",
    },
    async (event) => {
      const object = event.data;
      const filePath = object?.name || "";
      const bucketName = object?.bucket || "";
      const contentType = (object?.contentType || "").toLowerCase();
      const customMeta = object?.metadata || {};

      if (!filePath || !bucketName) {
        return null;
      }

      if (!filePath.startsWith("reports/")) {
        return null;
      }
      if (filePath.startsWith("reports/thumbs/")) {
        return null;
      }
      if (customMeta.derivative === "true") {
        return null;
      }
      if (!contentType.startsWith("image/")) {
        return null;
      }

      const bucket = getStorage().bucket(bucketName);
      const sourceFile = bucket.file(filePath);
      const ext = path.extname(filePath);
      const baseName = path.basename(filePath, ext || undefined);

      if (!baseName) {
        return null;
      }

      const tempSourcePath = path.join(os.tmpdir(), `${baseName}${ext || ""}`);
      const thumbBaseName = `${baseName}_640`;
      const tempThumbWebpPath = path.join(os.tmpdir(), `${thumbBaseName}.webp`);
      const tempThumbJpegPath = path.join(os.tmpdir(), `${thumbBaseName}.jpg`);
      const thumbWebpPath = `reports/thumbs/${thumbBaseName}.webp`;
      const thumbJpegPath = `reports/thumbs/${thumbBaseName}.jpg`;

      try {
        await sourceFile.download({destination: tempSourcePath});

        await sharp(tempSourcePath)
            .rotate()
            .resize({
              width: 640,
              height: 640,
              fit: "inside",
              withoutEnlargement: true,
            })
            .webp({quality: 78})
            .toFile(tempThumbWebpPath);

        await sharp(tempSourcePath)
            .rotate()
            .resize({
              width: 640,
              height: 640,
              fit: "inside",
              withoutEnlargement: true,
            })
            .jpeg({quality: 80, mozjpeg: true})
            .toFile(tempThumbJpegPath);

        const webpToken = crypto.randomUUID();
        const jpegToken = crypto.randomUUID();

        await bucket.upload(tempThumbWebpPath, {
          destination: thumbWebpPath,
          metadata: {
            contentType: "image/webp",
            cacheControl: "public, max-age=31536000, immutable",
            metadata: {
              derivative: "true",
              sourcePath: filePath,
              firebaseStorageDownloadTokens: webpToken,
            },
          },
        });

        await bucket.upload(tempThumbJpegPath, {
          destination: thumbJpegPath,
          metadata: {
            contentType: "image/jpeg",
            cacheControl: "public, max-age=31536000, immutable",
            metadata: {
              derivative: "true",
              sourcePath: filePath,
              firebaseStorageDownloadTokens: jpegToken,
            },
          },
        });

        const encodedWebpPath = encodeURIComponent(thumbWebpPath);
        const encodedJpegPath = encodeURIComponent(thumbJpegPath);
        const thumbWebpUrl = `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodedWebpPath}?alt=media&token=${webpToken}`;
        const thumbJpegUrl = `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodedJpegPath}?alt=media&token=${jpegToken}`;

        let originalDownloadUrl = "";
        try {
          originalDownloadUrl = await getDownloadURL(sourceFile);
        } catch (error) {
          console.warn("Unable to resolve original download URL:", error);
        }

        const firestore = getFirestore();
        let reportsSnapshot = await firestore.collection("reports")
            .where("mediaPath", "==", filePath)
            .limit(20)
            .get();

        if (reportsSnapshot.empty && originalDownloadUrl) {
          reportsSnapshot = await firestore.collection("reports")
              .where("mediaUrl", "==", originalDownloadUrl)
              .limit(20)
              .get();
        }

        if (reportsSnapshot.empty) {
          console.log("No report document matched source image:", filePath);
          return null;
        }

        const batch = firestore.batch();
        reportsSnapshot.docs.forEach((reportDoc) => {
          batch.update(reportDoc.ref, {
            mediaThumbPath: thumbJpegPath,
            mediaThumbUrl: thumbJpegUrl,
            mediaThumbWebpPath: thumbWebpPath,
            mediaThumbWebpUrl: thumbWebpUrl,
            mediaDerivativesAt: new Date().toISOString(),
          });
        });
        await batch.commit();

        console.log("Generated report image derivatives for:", filePath);
        return null;
      } catch (error) {
        console.error("Failed to generate report image derivatives:", error);
        return null;
      } finally {
        await Promise.allSettled([
          fs.unlink(tempSourcePath),
          fs.unlink(tempThumbWebpPath),
          fs.unlink(tempThumbJpegPath),
        ]);
      }
    });

/**
 * Optional: Clean up old notification tokens that are no longer valid
 * This function can be triggered periodically or manually
 */
exports.cleanupInvalidTokens = onDocumentCreated(
    {
      document: "token_cleanup/{cleanupId}",
      region: "asia-southeast1",
    },
    async (event) => {
      const db = getFirestore();
      const tokensSnapshot = await db.collection("user_tokens").get();
      const invalidTokens = [];

      // Test each token by trying to send a dry-run message
      for (const doc of tokensSnapshot.docs) {
        const data = doc.data();
        if (!data.fcmToken) continue;

        try {
          await getMessaging().send({
            token: data.fcmToken,
            data: {type: "test"},
          }, true); // dry run
        } catch (error) {
          // If token is invalid, mark for deletion
          if (error.code === "messaging/invalid-registration-token" ||
              error.code === "messaging/registration-token-not-registered") {
            invalidTokens.push(doc.id);
          }
        }
      }

      // Delete invalid tokens
      const batch = db.batch();
      invalidTokens.forEach((tokenId) => {
        batch.delete(db.collection("user_tokens").doc(tokenId));
      });

      await batch.commit();
      console.log(`Cleaned up ${invalidTokens.length} invalid tokens`);
      return {cleaned: invalidTokens.length};
    });

const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {initializeApp} = require("firebase-admin/app");
const {getMessaging} = require("firebase-admin/messaging");
const {getFirestore} = require("firebase-admin/firestore");

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

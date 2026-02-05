# Firebase Cloud Functions for RES-Q Push Notifications

This directory contains Firebase Cloud Functions that automatically send push notifications when:
1. An admin creates a new announcement
2. A new incident report is posted

## Setup Instructions

### Prerequisites
- Node.js 20 or higher installed (Node.js 18 was decommissioned on 2025-10-30)
  - Check your version: `node --version`
  - Download from: https://nodejs.org/
- Firebase CLI installed (`npm install -g firebase-tools`)
- Firebase project already configured (res-q-93ca6)

### Initial Setup

1. **Install Dependencies**
   ```bash
   cd functions
   npm install
   ```

2. **Login to Firebase**
   ```bash
   firebase login
   ```

3. **Set the Firebase Project**
   ```bash
   firebase use res-q-93ca6
   ```

4. **Deploy the Functions**
   ```bash
   firebase deploy --only functions
   ```

   Or deploy specific functions:
   ```bash
   firebase deploy --only functions:onAnnouncementCreated
   firebase deploy --only functions:onReportCreated
   ```

### Functions Overview

#### 1. onAnnouncementCreated
- **Trigger**: Firestore document created in `announcements` collection
- **Action**: Sends push notification to all users subscribed to "announcements" topic
- **Features**:
  - Skips placeholder announcements
  - Includes announcement title and content
  - Uses high priority for Android
  - Custom notification channel and icon

#### 2. onReportCreated
- **Trigger**: Firestore document created in `reports` collection
- **Action**: Sends push notification to all registered users
- **Features**:
  - Skips reports without location data
  - Sends to all users with valid FCM tokens
  - Includes incident type and location
  - Handles batch sending efficiently
  - Logs success and failure counts

#### 3. cleanupInvalidTokens (Optional)
- **Trigger**: Manual or scheduled trigger
- **Action**: Removes invalid/expired FCM tokens from database
- **Usage**: Create a document in `token_cleanup` collection to trigger

### Testing

1. **Local Emulator (Optional)**
   ```bash
   cd functions
   npm run serve
   ```

2. **Test in Production**
   - Create a new announcement in Firebase Console
   - Create a new report through the app
   - Check function logs: `firebase functions:log`

### Monitoring

View function logs:
```bash
firebase functions:log
```

View specific function logs:
```bash
firebase functions:log --only onAnnouncementCreated
firebase functions:log --only onReportCreated
```

### Troubleshooting

1. **Function not triggering**
   - Check Firebase Console > Functions for errors
   - Verify the function is deployed: `firebase functions:list`
   - Check function logs: `firebase functions:log`

2. **Notifications not received**
   - Verify users are subscribed to "announcements" topic
   - Check FCM tokens are saved in `user_tokens` collection
   - Verify app has notification permissions
   - Check device notification settings

3. **Token errors**
   - Run the `cleanupInvalidTokens` function periodically
   - Verify tokens are being refreshed in the app

### Cost Considerations

- Cloud Functions are billed based on:
  - Number of invocations
  - Compute time
  - Network egress
- Free tier includes:
  - 2M invocations/month
  - 400,000 GB-seconds
  - 200,000 CPU-seconds

For this app, the costs should be minimal as functions only trigger on document creation.

### Security

- Functions run with admin privileges
- No authentication required for triggers (Firestore triggers are internal)
- FCM tokens are stored securely in Firestore
- Functions validate data before sending notifications

### Future Enhancements

Possible improvements:
- Location-based notifications (send only to nearby users)
- Custom notification preferences per user
- Scheduled notification cleanup
- Rich notifications with images
- Action buttons in notifications
- Notification history tracking

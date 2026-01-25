# Admin Account Approval Flow

## Overview

This document explains the complete user registration and approval flow for the RES-Q app.

## User Registration Flow

### Step 1: Registration

1. User goes to the registration page
2. User fills in their details:
   - Full Name
   - Username
   - Email
   - Password
   - Contact Number (Phone)
   - Address
   - Date of Birth
   - ID Photo
3. User submits the registration form

### Step 2: OTP Verification

1. Firebase Auth sends a 6-digit OTP to the user's phone number
2. User enters the OTP code
3. System verifies the OTP
4. Upon successful verification, user is redirected to PIN creation

### Step 3: PIN Creation (During Registration)

1. User creates a 4-digit PIN
2. System saves the user data to `pending_users` collection in Firestore
3. User sees a modal: **"Account Pending Approval"**
   - Message: "Your account is currently pending admin approval. Please wait up to 48 hours..."
4. User is redirected to the login page

---

## Admin Approval Process

### Manually Approving Users (Firestore Console)

1. **Go to Firestore Database**
   - Navigate to Firebase Console → Firestore Database

2. **Check Pending Users**
   - Open the `pending_users` collection
   - Review user information (check if ID photo is valid, details are correct)

3. **Approve User**
   - Copy the user document data
   - Create a new document in `approved_users` collection with the same data
   - Update the following fields:
     - `accountStatus`: Change to `"approved"`
     - `approvedAt`: Add server timestamp
     - **IMPORTANT**: Remove the `pin` field (user will create a new PIN)
   - Delete the document from `pending_users` collection

### Using the SMS Service

To send an SMS notification when approving a user, you can use the `SmsService` class:

```dart
import 'package:res_q/services/sms_service.dart';

// Approve user and send SMS notification
await SmsService.approveUserAndNotify(userId);
```

**Setup Required:**

1. Open `lib/services/sms_service.dart`
2. Replace `YOUR_SEMAPHORE_API_KEY` with your actual API key
3. Choose your SMS provider:
   - **Semaphore** (Philippines) - `sendAccountApprovedSms()`
   - **Twilio** (International) - `sendAccountApprovedSmsTwilio()`

**Popular SMS Providers:**

- **Semaphore** (Philippines): https://semaphore.co/
- **Twilio** (Global): https://www.twilio.com/
- **AWS SNS** (Global): https://aws.amazon.com/sns/

---

## User PIN Creation Flow (After Approval)

### Step 1: User Receives SMS

After admin approves the account, user receives an SMS:

```
Hi [username]! Your RES-Q account has been approved by our admin.
You can now create your PIN and login to the app.
Click "Account Approved? Create PIN here" on the login page to get started.
```

### Step 2: Create PIN

1. User opens the app and goes to the login page
2. User clicks the link: **"Account Approved? Create PIN here"**
3. User enters their registered phone number
4. System checks if the phone number exists in `approved_users` collection
5. If approved, user is shown the PIN creation interface
6. User creates a 4-digit PIN using the numpad
7. System saves the PIN to the user's document in `approved_users`

### Step 3: Success Message

1. User is redirected to the login page
2. Green success message appears: **"Pin is good to go! Enter the pin in the pin section."**
3. User can now login using just their 4-digit PIN

---

## Login Flow

### PIN Login (Default)

1. User enters their registered phone number
2. User taps on the numpad to enter their 4-digit PIN
3. When the 4th digit is entered, the system automatically:
   - Queries `approved_users` collection for matching phone number + PIN combination
   - Checks if `accountStatus` is `"approved"`
   - Logs the user in if credentials are valid
4. User is redirected to the main page

**Note:** Phone number + PIN combination is required because multiple users can have the same PIN (only 4 digits = 10,000 possible combinations).

### Semi-Admin Login

1. User switches to "Semi-Admin" tab
2. User enters username and password
3. System checks `semi_admins` collection
4. If valid, user is redirected to the semi-admin dashboard

---

## Firestore Collections

### `pending_users`

Stores newly registered users awaiting admin approval.

**Fields:**

- `fullName`: string
- `username`: string
- `email`: string
- `password`: string (hashed recommended in production)
- `contactNumber`: string (format: +63XXXXXXXXXX)
- `address`: string
- `dateOfBirth`: string
- `idPhotoPath`: string
- `pin`: string (4 digits) - **Remove when approving**
- `accountStatus`: "pending"
- `createdAt`: timestamp
- `role`: "user"

### `approved_users`

Stores approved users who can login.

**Fields:**

- All fields from `pending_users`
- `accountStatus`: "approved"
- `approvedAt`: timestamp
- `pin`: string (4 digits) - Created by user after approval
- `pinCreatedAt`: timestamp

### `semi_admins`

Stores semi-admin accounts for staff.

**Fields:**

- `username`: string
- `fullName`: string
- `password`: string
- `role`: "semi-admin"

### `sms_logs`

Tracks all SMS notifications sent.

**Fields:**

- `phoneNumber`: string
- `username`: string
- `message`: string
- `status`: "sent" | "failed" | "error"
- `error`: string (if failed)
- `sentAt`: timestamp

---

## Important Notes

### Security Recommendations

1. **Password Hashing**: In production, use proper password hashing (e.g., bcrypt)
2. **PIN Security**: Consider encrypting PINs in the database
3. **SMS Provider**: Keep API keys secure (use environment variables)
4. **Rate Limiting**: Implement rate limiting on PIN attempts
5. **PIN Uniqueness**: PINs can be duplicated between users (only 4 digits). Phone numbers are the unique identifier.

### Testing

Default semi-admin accounts for testing:

- Username: `semiadmin1` to `semiadmin5`
- Password: `semi1234`

### User Experience

- PIN login is the primary login method (faster, easier)
- Users only need to remember their 4-digit PIN
- Semi-admin login is for staff members only

---

## Troubleshooting

### User can't create PIN

- Check if user exists in `approved_users` collection
- Verify `contactNumber` format is correct (+63XXXXXXXXXX)
- Check if `accountStatus` is "approved"

### SMS not sending

- Verify SMS provider API key is correct
- Check `sms_logs` collection for error messages
- Ensure phone number format is correct

### User can't login with PIN

- Verify PIN exists in `approved_users` document
- Check if `accountStatus` is "approved"
- Ensure PIN is exactly 4 digits

---

## Future Enhancements

1. **Admin Dashboard**: Build an admin panel to approve users from the app
2. **Batch Approval**: Allow admins to approve multiple users at once
3. **Auto-Approval**: Set criteria for automatic approval
4. **Email Notifications**: Send email in addition to SMS
5. **PIN Recovery**: Allow users to reset their PIN via OTP

# Quick Start Guide - User Registration & PIN Login Flow

## 🚀 For Users

### First Time Registration

1. **Register Your Account**
   - Open the app → Click "REGISTER"
   - Fill in all your details
   - Upload your ID photo
   - Click "Register"

2. **Verify Your Phone**
   - Receive 6-digit OTP via SMS
   - Enter the OTP code
   - Click "Verify"

3. **Wait for Approval**
   - You'll see: "Account Pending Approval"
   - Wait up to 48 hours
   - Admin will review your account

4. **Get Approved & Create PIN**
   - You'll receive SMS: "Your account has been approved!"
   - Open the app → Login page
   - Click: **"Account Approved? Create PIN here"**
   - Enter your registered phone number
   - Create a 4-digit PIN using the numpad
   - Done! You can now login

5. **Login with PIN**
   - Open the app → Login page
   - Enter your phone number (09XX-XXX-XXXX)
   - Enter your 4-digit PIN using the numpad
   - Automatic login when you enter the 4th digit
   - Access the app!

---

## 👨‍💼 For Admins

### Approving New Users

**Option 1: Manual Approval (Firestore Console)**

1. Go to Firebase Console → Firestore
2. Open `pending_users` collection
3. Review user details (ID photo, information)
4. If approved:
   - Copy the user document
   - Create document in `approved_users` with same data
   - Change `accountStatus` to `"approved"`
   - Add `approvedAt`: server timestamp
   - **REMOVE the `pin` field**
   - Delete from `pending_users`

**Option 2: Automated Approval (Code)**

```dart
import 'package:res_q/services/sms_service.dart';

// This will:
// - Move user to approved_users
// - Send SMS notification
// - Remove PIN (user creates new one)
await SmsService.approveUserAndNotify(userId);
```

### SMS Setup

1. Choose SMS provider:
   - **Semaphore** (Philippines): https://semaphore.co/
   - **Twilio** (Global): https://www.twilio.com/

2. Get API credentials

3. Open: `lib/services/sms_service.dart`

4. Replace placeholders:
   - For Semaphore: `YOUR_SEMAPHORE_API_KEY`
   - For Twilio: `YOUR_TWILIO_ACCOUNT_SID`, `YOUR_TWILIO_AUTH_TOKEN`, `YOUR_TWILIO_PHONE_NUMBER`

5. Save and restart the app

---

## 📱 User Interface Updates

### Login Page New Features

**New Link Added:**

- "Account Approved? Create PIN here" (below "Forgot Password")
- Click this after receiving approval SMS

**Success Banner:**

- Green banner appears after PIN creation
- Shows: "Pin is good to go! Enter the pin in the pin section."
- Auto-hides after 5 seconds

**PIN Entry:**

- Visual numpad (no keyboard)
- Dots show how many digits entered
- Auto-submits when 4 digits entered
- Clear (C) and Delete (⌫) buttons

---

## 🗄️ Database Structure

### Collections

**pending_users** - Awaiting approval

- All registration data
- Initial PIN (from registration)
- accountStatus: "pending"

**approved_users** - Can login

- All user data
- PIN (created after approval)
- accountStatus: "approved"
- approvedAt: timestamp

**semi_admins** - Staff accounts

- username, password, role

**sms_logs** - SMS tracking

- Records all SMS sent
- Tracks delivery status

---

## 🔑 Key Points

✅ **PIN is 4 digits only**
✅ **PINs can be the same between users** (different people can have same PIN)
✅ **Phone numbers MUST be unique** (no two users can have same phone)
✅ **Phone format: +63XXXXXXXXXX**
✅ **Users create PIN AFTER approval**
✅ **PIN during registration is temporary**
✅ **Final PIN is created via special link**
✅ **Auto-login when 4th digit entered**

---

## ⚠️ Important Notes

- **Users CANNOT login during pending status**
- **Admin must approve before PIN creation**
- **Old PIN is removed when approving**
- **Users get SMS when approved**
- **New PIN is required after approval**

---

## 🆘 Troubleshooting

**"Phone number not found"**
→ User not approved yet or wrong phone number

**"You already have a PIN"**
→ User already set up PIN, use normal login

**Can't receive OTP**
→ Check phone number format, Firebase Auth settings

**Can't login with PIN**
→ Verify accountStatus is "approved" in Firestore

**SMS not sending**
→ Check API credentials in sms_service.dart

---

## 📞 Support

For setup help or issues:

1. Check `ADMIN_APPROVAL_FLOW.md` for detailed guide
2. Check `IMPLEMENTATION_SUMMARY.md` for technical details
3. Review Firestore collections for data verification

---

## Default Credentials (Testing)

**Semi-Admin Login:**

- Username: `semiadmin1` to `semiadmin5`
- Password: `semi1234`

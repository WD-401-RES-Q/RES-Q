# Firebase Phone Authentication Setup Guide

## ✅ What's Been Implemented

### 1. **Registration Flow**

- User fills registration form with contact number
- Phone number is automatically formatted (adds +63 for Philippines)
- Firebase sends OTP to the phone number
- User data is temporarily stored and passed to OTP page

### 2. **OTP Verification**

- 6-digit OTP input with brand colors (red/yellow/green)
- Real-time verification with Firebase
- **Error handling**: If OTP is incorrect, shows error and allows retry
- OTP field clears on error for easy re-entry
- Resend OTP functionality

### 3. **Data Storage**

- After successful OTP verification, user data is saved to Firestore
- User collection includes: fullName, username, email, contactNumber, address, dateOfBirth, idPhotoPath

## 📋 Firebase Console Setup Required

### Enable Phone Authentication:

1. Go to Firebase Console → Authentication → Sign-in method
2. Enable "Phone" provider
3. Add test phone numbers if needed (for development)

### Firestore Setup:

1. Go to Firestore Database
2. Create database (Start in test mode for development)
3. User data will be automatically saved to `users` collection

### For Android Testing:

1. Get SHA-1 certificate:
   ```
   cd android
   ./gradlew signingReport
   ```
2. Add SHA-1 to Firebase Console → Project Settings → Your apps
3. Download updated `google-services.json`

## 🎨 Design Features Maintained

- **Brand Colors**: Red (#AC1B22), Yellow (#FFC806), Green (#00A458)
- **Typography**: Poppins for headings, Quicksand for body
- **Clean UI**: Consistent with your app design
- **Error Messages**: Styled with brand colors

## 📱 Phone Number Format

The app automatically handles phone formatting:

- Input: `09171234567` → Formatted: `+639171234567`
- Input: `9171234567` → Formatted: `+639171234567`
- Input: `+639171234567` → No change

## 🧪 Testing

### Test Phone Numbers (Development):

In Firebase Console → Authentication → Sign-in method → Phone → Add test phone:

- Phone: `+1 650-555-3434` → Code: `123456`
- (Add your own test numbers)

### Real Testing:

1. Use a real Philippine number
2. Enter registration details
3. Click "CREATE ACCOUNT"
4. Wait for SMS OTP
5. Enter OTP on verification screen
6. If wrong, clear and try again

## ⚠️ Error Scenarios Handled

1. **Invalid OTP**: Shows "Invalid OTP code. Please try again." - OTP field clears
2. **Expired OTP**: Shows "OTP expired. Please request a new code."
3. **Invalid Phone**: Shows error during registration
4. **Network Issues**: Displays relevant error message

## 🔄 Retry Logic

- User can enter OTP multiple times
- "Resend code" button available
- No limit on retry attempts (Firebase handles rate limiting)

## 📊 Data Structure in Firestore

```
users/
  └── {userId}/
      ├── fullName: string
      ├── username: string
      ├── email: string
      ├── contactNumber: string
      ├── address: string
      ├── dateOfBirth: string
      ├── idPhotoPath: string
      └── createdAt: timestamp
```

## 🚀 Next Steps

1. Enable Phone Authentication in Firebase Console
2. Test with test phone numbers first
3. Add real SHA-1 certificate for production
4. Test complete flow: Register → OTP → Main Page
5. Implement profile picture upload to Firebase Storage

## 📞 Support

If OTP is not received:

- Check Firebase Console logs
- Verify phone number format
- Check SMS quota in Firebase (free tier has limits)
- Ensure test mode numbers are configured for development

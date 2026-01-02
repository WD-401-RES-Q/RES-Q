# Account Approval System - Complete Guide

## Overview

The RES-Q app now has a complete account approval workflow where new user registrations must be approved by admins before they can login.

## User Registration Flow

### 1. Registration

- User fills out registration form with:
  - Full name, username, email, password
  - Contact number, address, date of birth
  - ID photo
- Submits the form

### 2. OTP Verification

- User receives OTP on their phone
- Enters the 6-digit OTP code
- System verifies the code

### 3. Account Created (Pending Status)

- Upon successful OTP verification:
  - Account is created in Firestore with `accountStatus: 'pending'`
  - User sees a modal: "Registration Successful! Your account is pending admin approval. You will be able to login within 48 hours."
  - User is redirected to the login page

### 4. Login Attempt (Before Approval)

- If user tries to login with pending account:
  - System checks `accountStatus` field
  - Shows modal: "Account Pending Approval - Please wait up to 48 hours for admin review"
  - Login is blocked

## Admin Approval Flow (Web App)

### Admin Dashboard

The web app (`res_qwebapp`) now has an Account Approval component with three tabs:

#### 1. Pending Accounts Tab

- Shows all users with `accountStatus: 'pending'`
- Displays:
  - Full name, username, email
  - Phone number, address
  - Date of birth
  - Registration timestamp
- Actions:
  - **Approve Button**: Approves the account
  - **Reject Button**: Opens rejection dialog

#### 2. Approved Accounts Tab

- Lists all approved users
- Shows approval timestamp and who approved it

#### 3. Rejected Accounts Tab

- Lists all rejected users
- Shows rejection reason, timestamp, and who rejected it

### Admin Actions

**Approving an Account:**

1. Click "Approve" button
2. Confirm the approval
3. System updates:
   - `accountStatus: 'approved'`
   - `approvedAt: <timestamp>`
   - `approvedBy: <admin_username>`
4. User can now login

**Rejecting an Account:**

1. Click "Reject" button
2. Enter rejection reason in dialog
3. Confirm rejection
4. System updates:
   - `accountStatus: 'rejected'`
   - `rejectedAt: <timestamp>`
   - `rejectedBy: <admin_username>`
   - `rejectionReason: <reason>`
5. User sees rejection message when trying to login

## Database Structure

### Users Collection

Each user document has these fields:

```typescript
{
  username: string;
  fullName: string;
  email: string;
  password: string;
  contactNumber: string;
  address: string;
  dateOfBirth: string;
  accountStatus: 'pending' | 'approved' | 'rejected';
  createdAt: Timestamp;

  // Approval fields (if approved)
  approvedAt?: Timestamp;
  approvedBy?: string;

  // Rejection fields (if rejected)
  rejectedAt?: Timestamp;
  rejectedBy?: string;
  rejectionReason?: string;
}
```

## Using the Admin Component

### In Your Angular App Routes

Add the component to your routes:

```typescript
import { AccountApprovalComponent } from "./app/account-approval.component";

export const routes: Routes = [
  {
    path: "admin/approvals",
    component: AccountApprovalComponent,
  },
  // ... other routes
];
```

### Standalone Usage

The component is standalone and can be used directly:

```typescript
import { AccountApprovalComponent } from "./app/account-approval.component";

// In your component template
<app-account-approval></app-account-approval>;
```

## Security Considerations

1. **Admin Authentication**: In production, implement proper admin authentication
2. **Authorization**: Verify admin permissions before allowing approval/rejection
3. **Audit Trail**: All approvals/rejections are logged with timestamps and admin usernames
4. **Password Security**: Passwords should be hashed (consider implementing proper hashing)

## Mobile App Login Logic

The mobile app checks account status:

- `pending` → Shows "Pending Approval" modal
- `rejected` → Shows "Account Rejected" message
- `approved` → Allows login if password is correct
- Semi-admins bypass approval (different collection)

## Testing the Flow

1. **Register a new user** in mobile app
2. **Verify OTP** - should see approval pending message
3. **Try to login** - should see pending approval modal
4. **Open web app** - go to approvals page
5. **Approve the user** from admin dashboard
6. **Login in mobile app** - should now work!

## API Methods (Firestore Service)

```typescript
// Get pending users
await firestoreService.getPendingUsers();

// Approve a user
await firestoreService.approveUser(userId, adminUsername);

// Reject a user
await firestoreService.rejectUser(userId, adminUsername, reason);

// Get approved users
await firestoreService.getApprovedUsers();

// Get rejected users
await firestoreService.getRejectedUsers();
```

## Summary

✅ **Complete registration flow with OTP**
✅ **Pending approval system**
✅ **48-hour grace period messaging**
✅ **Admin approval dashboard**
✅ **Approve/Reject functionality**
✅ **Status-based login control**
✅ **Audit trail for all actions**

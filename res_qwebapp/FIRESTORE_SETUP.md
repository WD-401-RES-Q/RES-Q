# RES-Q Web App - Firestore Setup

## Firebase/Firestore Configuration

The web app is now connected to the same Firestore database as the Flutter mobile app.

### Setup Instructions

1. **Install dependencies:**

   ```bash
   npm install
   ```

2. **Run the development server:**
   ```bash
   npm start
   ```

### Firebase Configuration

The app is configured to connect to the Firestore database with project ID: `res-q-93ca6`

Configuration file: `src/app/firebase.config.ts`

### Using Firestore in Your Components

#### 1. Import the FirestoreService

```typescript
import { FirestoreService } from './firestore.service';
```

#### 2. Inject it in your component constructor

```typescript
constructor(private firestoreService: FirestoreService) {}
```

#### 3. Use the service methods

**Get all users:**

```typescript
const users = await this.firestoreService.getUsers();
```

**Get all semi-admins:**

```typescript
const semiAdmins = await this.firestoreService.getSemiAdmins();
```

**Get user by username:**

```typescript
const user = await this.firestoreService.getUserByUsername('johndoe');
```

**Query any collection:**

```typescript
const results = await this.firestoreService.queryCollection(
  'users',
  'email',
  '==',
  'user@example.com'
);
```

**Add a document:**

```typescript
const docId = await this.firestoreService.addDocument('users', {
  username: 'newuser',
  email: 'new@example.com',
  // ... other fields
});
```

**Update a document:**

```typescript
await this.firestoreService.updateDocument('users', userId, {
  email: 'updated@example.com',
});
```

**Delete a document:**

```typescript
await this.firestoreService.deleteDocument('users', userId);
```

### Available Collections

- `users` - Regular app users
- `semi_admins` - Semi-admin users

### Database Structure

**Users Collection:**

- `username`: string
- `email`: string
- `password`: string (hashed)
- `fullName`: string
- `contactNumber`: string
- `address`: string
- `dateOfBirth`: string
- `role`: string
- `createdAt`: timestamp

**Semi Admins Collection:**

- `username`: string
- `password`: string
- Other admin-specific fields

### Example Component

See `src/app/example-usage.component.ts` for a complete example of how to use Firestore in your components.

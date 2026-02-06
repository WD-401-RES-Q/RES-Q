# RES-Q AES-256-GCM Encryption

## Overview

RES-Q uses **AES-256-GCM** encryption to protect user PII (Personally Identifiable Information) at rest in Firestore. This document explains the encryption architecture, implementation details, and security boundaries.

---

## Encryption Architecture

```
╔══════════════════════════════════════════════════════════════════════════╗
║                        ENCRYPTION FLOW                                   ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  [MOBILE APP]                    [CLOUD FUNCTIONS]        [FIRESTORE]    ║
║      │                                 │                      │          ║
║      │  1. User fills form             │                      │          ║
║      │     (plaintext PII)             │                      │          ║
║      │                                 │                      │          ║
║      │  2. Phone OTP verified ─────────┼──────────────────────│          ║
║      │                                 │                      │          ║
║      │  3. Call registerUserEncrypted()│                      │          ║
║      │ ─────────────────────────────►  │                      │          ║
║      │     (HTTPS, plaintext JSON)     │                      │          ║
║      │                                 │                      │          ║
║      │                    4. Encrypt PII fields:              │          ║
║      │                       • fullName                       │          ║
║      │                       • email                          │          ║
║      │                       • contactNumber                  │          ║
║      │                       • address                        │          ║
║      │                       • dateOfBirth                    │          ║
║      │                                 │                      │          ║
║      │                    5. Store encrypted ─────────────────│►         ║
║      │                       (base64 ciphertext)              │          ║
║      │                                 │                      │          ║
║      │ ◄───────────────────────────── │     [Encrypted]      │          ║
║      │   6. Success response           │        Data          │          ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

---

## AES-256-GCM Details

| Property       | Value                                                 |
| -------------- | ----------------------------------------------------- |
| **Algorithm**  | AES (Advanced Encryption Standard)                    |
| **Key Size**   | 256 bits (32 bytes)                                   |
| **Mode**       | GCM (Galois/Counter Mode)                             |
| **IV (Nonce)** | 96 bits (12 bytes), randomly generated per encryption |
| **Auth Tag**   | 128 bits (16 bytes), ensures data integrity           |

### Why AES-256-GCM?

- **CONFIDENTIALITY**: 256-bit key is computationally infeasible to crack
- **INTEGRITY**: GCM mode provides authentication tag to detect tampering
- **PERFORMANCE**: Hardware-accelerated on modern CPUs (AES-NI)
- **STANDARD**: NIST-approved, widely used (TLS 1.3, SSH, etc.)

### Ciphertext Format

The encrypted output is Base64-encoded with the following structure:

```
┌──────────┬──────────────┬─────────────────────┐
│ IV       │ Auth Tag     │ Encrypted Data      │
│ 12 bytes │ 16 bytes     │ Variable length     │
└──────────┴──────────────┴─────────────────────┘
```

---

## Decryption Flow (Admin Only)

```
╔══════════════════════════════════════════════════════════════════════════╗
║                        DECRYPTION FLOW                                   ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  [ADMIN WEB APP]              [CLOUD FUNCTIONS]          [FIRESTORE]     ║
║      │                              │                         │          ║
║      │  1. Admin authenticated      │                         │          ║
║      │     (Firebase Auth)          │                         │          ║
║      │                              │                         │          ║
║      │  2. Request user data        │                         │          ║
║      │ ────────────────────────►   │                         │          ║
║      │    decryptUserData()         │                         │          ║
║      │                              │                         │          ║
║      │                 3. Verify admin ID ───────────────────►│          ║
║      │                    (check admins collection)           │          ║
║      │                              │                         │          ║
║      │                 4. Fetch encrypted data ◄──────────────│          ║
║      │                              │                         │          ║
║      │                 5. Decrypt using master key            │          ║
║      │                    (server-side only)                  │          ║
║      │                              │                         │          ║
║      │ ◄────────────────────────── │                         │          ║
║      │   6. Return plaintext        │                         │          ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

---

## Key Management

### Master Key Storage

- Stored in **Firebase Functions config** (environment variable)
- **Never exposed** to client apps (mobile or web)
- Set via: `firebase functions:config:set encryption.masterkey="<base64-encoded-32-byte-key>"`

### Security Boundaries

```
┌────────────────────┐    ┌────────────────────┐
│    MOBILE APP      │    │   ADMIN WEB APP    │
│  ─────────────     │    │  ───────────────   │
│  • No access to    │    │  • No access to    │
│    master key      │    │    master key      │
│  • Sends plaintext │    │  • Receives        │
│    over HTTPS      │    │    plaintext from  │
│  • Cannot decrypt  │    │    Cloud Function  │
└────────────────────┘    └────────────────────┘
          │                        │
          │         HTTPS          │
          ▼                        ▼
┌─────────────────────────────────────────────────┐
│              CLOUD FUNCTIONS                    │
│  ─────────────────────────────────────────────  │
│  • Master key access                            │
│  • Encryption/decryption operations             │
│  • Admin authentication verification            │
└─────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│                 FIRESTORE                       │
│  ─────────────────────────────────────────────  │
│  • Stores ONLY encrypted PII                    │
│  • Even if DB is breached, data is protected    │
│  • Encryption flag marks encrypted fields       │
└─────────────────────────────────────────────────┘
```

---

## Cloud Functions

Located in: `functions/src/index.ts`

| Function                  | Description                                     |
| ------------------------- | ----------------------------------------------- |
| `registerUserEncrypted()` | Encrypts PII during user registration           |
| `decryptUserData()`       | Decrypts a single user's data (admin only)      |
| `getDecryptedUsers()`     | Decrypts all users in a collection (admin only) |
| `migrateToEncrypted()`    | One-time migration of existing unencrypted data |

---

## Encrypted Fields (PII)

The following fields are encrypted before storage:

1. `fullName`
2. `email`
3. `contactNumber`
4. `address`
5. `dateOfBirth`

Each encrypted field has a corresponding `<fieldName>_encrypted: true` flag to indicate encryption status.

---

## Database Structure

### Firestore Collections

```
pending_users/
  └── {documentId}
      ├── fullName: "encrypted_base64..."
      ├── fullName_encrypted: true
      ├── email: "encrypted_base64..."
      ├── email_encrypted: true
      ├── contactNumber: "encrypted_base64..."
      ├── contactNumber_encrypted: true
      ├── address: "encrypted_base64..."
      ├── address_encrypted: true
      ├── dateOfBirth: "encrypted_base64..."
      ├── dateOfBirth_encrypted: true
      ├── idPhotoFront: "https://..." (not encrypted)
      ├── role: "user" (not encrypted)
      ├── status: "pending" (not encrypted)
      ├── _encryptedAt: Timestamp
      └── registeredAt: Timestamp

approved_users/
  └── (same structure)

rejected_users/
  └── (same structure)
```

---

## Implementation Example

### Encryption (Cloud Function)

```typescript
static encrypt(plaintext: string): string {
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
```

### Decryption (Cloud Function)

```typescript
static decrypt(ciphertext: string): string {
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
```

---

## Setting Up the Master Key

### Generate a secure 32-byte key:

```bash
# Using OpenSSL
openssl rand -base64 32
```

### Configure Firebase Functions:

```bash
firebase functions:config:set encryption.masterkey="YOUR_BASE64_KEY_HERE"
```

### Deploy:

```bash
firebase deploy --only functions
```

---

## Security Considerations

1. **Master Key Rotation**: If key rotation is needed, implement a re-encryption migration
2. **Backup Keys**: Store master key backup in a secure vault (not in source control)
3. **HTTPS Only**: All communication uses HTTPS (enforced by Firebase)
4. **Admin Verification**: Decryption functions verify admin identity before processing
5. **No Client-Side Keys**: Encryption keys never leave Cloud Functions environment

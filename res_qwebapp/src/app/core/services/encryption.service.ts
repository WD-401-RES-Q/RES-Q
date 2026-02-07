import { Injectable } from '@angular/core';

/**
 * AES-256-GCM Encryption Service
 * 
 * Uses Web Crypto API for secure client-side encryption/decryption.
 * Master key is stored encrypted and unlocked via admin authentication.
 */
@Injectable({
  providedIn: 'root'
})
export class EncryptionService {
  private masterKey: CryptoKey | null = null;
  private encoder = new TextEncoder();
  private decoder = new TextDecoder();

  // PII fields that should be encrypted
  static readonly PII_FIELDS = [
    'fullName',
    'email',
    'address',
    'dateOfBirth',
    'contactNumber'
  ];

  /**
   * Derive a key from password using PBKDF2
   */
  async deriveKeyFromPassword(password: string, salt: Uint8Array): Promise<CryptoKey> {
    const passwordBuffer = this.encoder.encode(password);
    
    // Import password as raw key material
    const keyMaterial = await crypto.subtle.importKey(
      'raw',
      passwordBuffer,
      'PBKDF2',
      false,
      ['deriveKey']
    );

    // Derive AES-256 key using PBKDF2
    return crypto.subtle.deriveKey(
      {
        name: 'PBKDF2',
        salt: salt as BufferSource,
        iterations: 100000,
        hash: 'SHA-256'
      },
      keyMaterial,
      { name: 'AES-GCM', length: 256 },
      true,
      ['encrypt', 'decrypt']
    );
  }

  /**
   * Generate a random master key
   */
  async generateMasterKey(): Promise<CryptoKey> {
    return crypto.subtle.generateKey(
      { name: 'AES-GCM', length: 256 },
      true,
      ['encrypt', 'decrypt']
    );
  }

  /**
   * Export a CryptoKey to base64 string
   */
  async exportKey(key: CryptoKey): Promise<string> {
    const exported = await crypto.subtle.exportKey('raw', key);
    return this.arrayBufferToBase64(exported);
  }

  /**
   * Import a base64 string as CryptoKey
   */
  async importKey(keyBase64: string): Promise<CryptoKey> {
    const keyBuffer = this.base64ToArrayBuffer(keyBase64);
    return crypto.subtle.importKey(
      'raw',
      keyBuffer,
      { name: 'AES-GCM', length: 256 },
      true,
      ['encrypt', 'decrypt']
    );
  }

  /**
   * Encrypt the master key with admin's derived key
   */
  async encryptMasterKey(masterKey: CryptoKey, adminDerivedKey: CryptoKey): Promise<string> {
    const masterKeyExported = await crypto.subtle.exportKey('raw', masterKey);
    const iv = crypto.getRandomValues(new Uint8Array(12));
    
    const encrypted = await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv: iv },
      adminDerivedKey,
      masterKeyExported
    );

    // Combine IV + encrypted data
    const combined = new Uint8Array(iv.length + encrypted.byteLength);
    combined.set(iv);
    combined.set(new Uint8Array(encrypted), iv.length);

    return this.arrayBufferToBase64(combined.buffer);
  }

  /**
   * Decrypt the master key with admin's derived key
   */
  async decryptMasterKey(encryptedMasterKey: string, adminDerivedKey: CryptoKey): Promise<CryptoKey> {
    const combined = this.base64ToArrayBuffer(encryptedMasterKey);
    const combinedArray = new Uint8Array(combined);
    
    // Extract IV (first 12 bytes) and encrypted data
    const iv = combinedArray.slice(0, 12);
    const encryptedData = combinedArray.slice(12);

    const decrypted = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: iv },
      adminDerivedKey,
      encryptedData
    );

    return crypto.subtle.importKey(
      'raw',
      decrypted,
      { name: 'AES-GCM', length: 256 },
      true,
      ['encrypt', 'decrypt']
    );
  }

  /**
   * Set the master key for the current session
   */
  setMasterKey(key: CryptoKey): void {
    this.masterKey = key;
  }

  /**
   * Clear the master key (on logout)
   */
  clearMasterKey(): void {
    this.masterKey = null;
  }

  /**
   * Check if master key is loaded
   */
  hasMasterKey(): boolean {
    return this.masterKey !== null;
  }

  /**
   * Encrypt a string using AES-256-GCM
   */
  async encrypt(plaintext: string): Promise<string> {
    if (!this.masterKey) {
      throw new Error('Master key not loaded');
    }

    const iv = crypto.getRandomValues(new Uint8Array(12));
    const plaintextBuffer = this.encoder.encode(plaintext);

    const encrypted = await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv: iv },
      this.masterKey,
      plaintextBuffer
    );

    // Combine IV + encrypted data + tag (GCM includes auth tag in output)
    const combined = new Uint8Array(iv.length + encrypted.byteLength);
    combined.set(iv);
    combined.set(new Uint8Array(encrypted), iv.length);

    return this.arrayBufferToBase64(combined.buffer);
  }

  /**
   * Decrypt a string using AES-256-GCM
   */
  async decrypt(ciphertext: string): Promise<string> {
    if (!this.masterKey) {
      throw new Error('Master key not loaded');
    }

    try {
      const combined = this.base64ToArrayBuffer(ciphertext);
      const combinedArray = new Uint8Array(combined);

      // Extract IV (first 12 bytes) and encrypted data
      const iv = combinedArray.slice(0, 12);
      const encryptedData = combinedArray.slice(12);

      const decrypted = await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv: iv },
        this.masterKey,
        encryptedData
      );

      return this.decoder.decode(decrypted);
    } catch (error) {
      console.error('Decryption failed:', error);
      throw new Error('Failed to decrypt data - invalid key or corrupted data');
    }
  }

  /**
   * Encrypt all PII fields in a user object
   */
  async encryptUserData(userData: Record<string, unknown>): Promise<Record<string, unknown>> {
    const encrypted = { ...userData };

    for (const field of EncryptionService.PII_FIELDS) {
      if (encrypted[field] && typeof encrypted[field] === 'string') {
        encrypted[field] = await this.encrypt(encrypted[field] as string);
        encrypted[`${field}_encrypted`] = true;
      }
    }

    return encrypted;
  }

  /**
   * Decrypt all PII fields in a user object
   */
  async decryptUserData(userData: Record<string, unknown>): Promise<Record<string, unknown>> {
    const decrypted = { ...userData };

    for (const field of EncryptionService.PII_FIELDS) {
      if (decrypted[field] && decrypted[`${field}_encrypted`]) {
        try {
          decrypted[field] = await this.decrypt(decrypted[field] as string);
        } catch (error) {
          console.error(`Failed to decrypt field ${field}:`, error);
          decrypted[field] = '[Decryption Failed]';
        }
      }
    }

    return decrypted;
  }

  /**
   * Hash a password using SHA-256 (for storage comparison)
   */
  async hashPassword(password: string, salt: string): Promise<string> {
    const data = this.encoder.encode(password + salt);
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    return this.arrayBufferToBase64(hashBuffer);
  }

  /**
   * Generate a random salt
   */
  generateSalt(): string {
    const salt = crypto.getRandomValues(new Uint8Array(16));
    return this.arrayBufferToBase64(salt.buffer);
  }

  /**
   * Convert ArrayBuffer to base64 string
   */
  private arrayBufferToBase64(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary);
  }

  /**
   * Convert base64 string to ArrayBuffer
   */
  private base64ToArrayBuffer(base64: string): ArrayBuffer {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes.buffer;
  }
}

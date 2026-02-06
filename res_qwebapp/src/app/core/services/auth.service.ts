import { Injectable, signal } from '@angular/core';
import { Router } from '@angular/router';
import { collection, query, where, getDocs, getDoc, doc, updateDoc } from 'firebase/firestore';
import { db } from '../config/firebase.config';

export interface Admin {
  id: string;
  username: string;
  passwordHash?: string;  // Hashed password
  passwordSalt?: string;  // Salt for hashing
  password?: string;      // Legacy plaintext (to be migrated)
  email: string;
  role: string;
  createdAt: Date;
}

@Injectable({
  providedIn: 'root'
})
export class AuthService {
  private currentAdminSignal = signal<Admin | null>(null);
  currentAdmin = this.currentAdminSignal.asReadonly();
  private encoder = new TextEncoder();

  constructor(private router: Router) {
    // Check if user is already logged in
    const storedAdmin = localStorage.getItem('currentAdmin');
    if (storedAdmin) {
      this.currentAdminSignal.set(JSON.parse(storedAdmin));
    }
  }

  /**
   * Hash a password using SHA-256 with salt
   */
    public async hashPassword(password: string, salt: string): Promise<string> {
    const data = this.encoder.encode(password + salt);
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    return this.arrayBufferToBase64(hashBuffer);
  }

  /**
   * Generate a random salt
   */
  private generateSalt(): string {
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

  async login(username: string, password: string): Promise<boolean> {
    try {
      // Query the admins collection by username only
      const adminsRef = collection(db, 'admins');
      const q = query(
        adminsRef,
        where('username', '==', username),
        where('role', '==', 'admin')
      );

      const querySnapshot = await getDocs(q);

      if (querySnapshot.empty) {
        return false;
      }

      const adminDoc = querySnapshot.docs[0];
      const adminData = adminDoc.data();

      // Check if using new hashed password system
      if (adminData['passwordHash'] && adminData['passwordSalt']) {
        const inputHash = await this.hashPassword(password, adminData['passwordSalt']);
        
        if (inputHash !== adminData['passwordHash']) {
          return false;
        }
      } else if (adminData['password']) {
        // Legacy plaintext password comparison
        // After successful login, migrate to hashed password
        if (adminData['password'] !== password) {
          return false;
        }

        // Migrate to hashed password
        await this.migratePassword(adminDoc.id, password);
        console.log('Admin password migrated to hashed format');
      } else {
        return false;
      }

      const admin: Admin = {
        id: adminDoc.id,
        ...adminData
      } as Admin;

      // Remove sensitive data before storing
      const safeAdmin = { ...admin };
      delete safeAdmin.password;
      delete safeAdmin.passwordHash;
      delete safeAdmin.passwordSalt;

      // Store admin data
      this.currentAdminSignal.set(safeAdmin);
      localStorage.setItem('currentAdmin', JSON.stringify(safeAdmin));

      return true;
    } catch (error) {
      console.error('Login error:', error);
      return false;
    }
  }

  /**
   * Verify the currently-authenticated admin's password by checking the stored hash/salt (or legacy plaintext).
   * Used for sensitive UI actions like viewing decrypted user data.
   */
  async verifyCurrentAdminPassword(password: string): Promise<boolean> {
    try {
      const admin = this.currentAdminSignal();
      if (!admin?.id) {
        return false;
      }

      const adminRef = doc(db, 'admins', admin.id);
      const snapshot = await getDoc(adminRef);
      if (!snapshot.exists()) {
        return false;
      }

      const adminData = snapshot.data() as Record<string, any>;
      if (adminData['role'] && adminData['role'] !== 'admin') {
        return false;
      }

      if (adminData['passwordHash'] && adminData['passwordSalt']) {
        const inputHash = await this.hashPassword(password, adminData['passwordSalt']);
        return inputHash === adminData['passwordHash'];
      }

      if (adminData['password']) {
        const ok = adminData['password'] === password;
        if (ok) {
          await this.migratePassword(admin.id, password);
        }
        return ok;
      }

      return false;
    } catch (error) {
      console.error('Password verification error:', error);
      return false;
    }
  }

  /**
   * Migrate plaintext password to hashed format
   */
  private async migratePassword(adminId: string, plainPassword: string): Promise<void> {
    try {
      const salt = this.generateSalt();
      const hash = await this.hashPassword(plainPassword, salt);

      const adminRef = doc(db, 'admins', adminId);
      await updateDoc(adminRef, {
        passwordHash: hash,
        passwordSalt: salt,
        password: null  // Remove plaintext password
      });
    } catch (error) {
      console.error('Failed to migrate password:', error);
      // Don't throw - login should still succeed
    }
  }

  logout(): void {
    this.currentAdminSignal.set(null);
    localStorage.removeItem('currentAdmin');
    this.router.navigate(['/admin/login']);
  }

  isAuthenticated(): boolean {
    return this.currentAdmin() !== null;
  }
}

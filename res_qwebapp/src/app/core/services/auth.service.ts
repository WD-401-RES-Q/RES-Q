import { Injectable, signal } from '@angular/core';
import { Router } from '@angular/router';
import { collection, query, where, getDocs } from 'firebase/firestore';
import { db } from '../config/firebase.config';

export interface Admin {
  id: string;
  username: string;
  password: string;
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

  constructor(private router: Router) {
    // Check if user is already logged in
    const storedAdmin = localStorage.getItem('currentAdmin');
    if (storedAdmin) {
      this.currentAdminSignal.set(JSON.parse(storedAdmin));
    }
  }

  async login(username: string, password: string): Promise<boolean> {
    try {
      // Query the admins collection
      const adminsRef = collection(db, 'admins');
      const q = query(
        adminsRef,
        where('username', '==', username),
        where('password', '==', password),
        where('role', '==', 'admin')
      );

      const querySnapshot = await getDocs(q);

      if (!querySnapshot.empty) {
        const adminDoc = querySnapshot.docs[0];
        const adminData = {
          id: adminDoc.id,
          ...adminDoc.data()
        } as Admin;

        // Store admin data
        this.currentAdminSignal.set(adminData);
        localStorage.setItem('currentAdmin', JSON.stringify(adminData));

        return true;
      }

      return false;
    } catch (error) {
      console.error('Login error:', error);
      return false;
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

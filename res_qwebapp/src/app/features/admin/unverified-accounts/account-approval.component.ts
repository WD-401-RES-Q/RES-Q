import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { FirestoreService } from '../../../core/services/firestore.service';
import { AuthService } from '../../../core/services/auth.service';

interface PendingUser {
  id: string;
  fullName: string;
  email: string;
  contactNumber: string;
  address: string;
  dateOfBirth: string;
  createdAt: any;
  accountStatus: string;
  approvedAt?: any;
  approvedBy?: string;
  rejectedAt?: any;
  rejectedBy?: string;
  rejectionReason?: string;
  [key: string]: any; // Index signature for dynamic property access
}

@Component({
  selector: 'app-account-approval',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './account-approval.component.html',
  styleUrls: ['./account-approval.component.scss']
})
export class AccountApprovalComponent implements OnInit {
  activeTab: 'pending' | 'approved' | 'rejected' = 'pending';
  pendingUsers: PendingUser[] = [];
  approvedUsers: PendingUser[] = [];
  rejectedUsers: PendingUser[] = [];
  loading = false;
  processing = false;
  
  showingRejectDialog = false;
  selectedUser: PendingUser | null = null;
  rejectionReason = '';

  // Admin username - should come from auth service in production
  adminUsername = 'admin'; // TODO: Get from authenticated admin user

  constructor(
    private firestoreService: FirestoreService,
    private authService: AuthService
  ) {}

  ngOnInit() {
    this.loadPendingUsers();
  }

  private getAdminId(): string {
    const admin = this.authService.currentAdmin();
    return admin?.id || '';
  }

  async loadPendingUsers() {
    this.loading = true;
    try {
      const adminId = this.getAdminId();
      // Use decrypted data if admin is authenticated
      if (adminId) {
        this.pendingUsers = await this.firestoreService.getDecryptedPendingUsers(adminId);
      } else {
        // Fallback to raw data (will show encrypted values)
        this.pendingUsers = await this.firestoreService.getPendingUsers();
      }
      console.log('Loaded pending users:', this.pendingUsers);
      console.log('Number of pending users:', this.pendingUsers.length);
      if (this.pendingUsers.length > 0) {
        console.log('First pending user:', this.pendingUsers[0]);
      }
    } catch (error) {
      console.error('Error loading pending users:', error);
    } finally {
      this.loading = false;
    }
  }

  async loadApprovedUsers() {
    this.loading = true;
    try {
      const adminId = this.getAdminId();
      if (adminId) {
        this.approvedUsers = await this.firestoreService.getDecryptedApprovedUsers(adminId);
      } else {
        this.approvedUsers = await this.firestoreService.getApprovedUsers();
      }
    } catch (error) {
      console.error('Error loading approved users:', error);
    } finally {
      this.loading = false;
    }
  }

  async loadRejectedUsers() {
    this.loading = true;
    try {
      this.rejectedUsers = await this.firestoreService.getRejectedUsers();
    } catch (error) {
      console.error('Error loading rejected users:', error);
    } finally {
      this.loading = false;
    }
  }

  async approveUser(user: PendingUser) {
    if (!confirm(`Are you sure you want to approve ${user.fullName}?`)) {
      return;
    }

    this.processing = true;
    try {
      await this.firestoreService.approvePendingUser(user, this.adminUsername);
      alert(`${user.fullName} has been approved successfully!`);
      await this.loadPendingUsers();
    } catch (error) {
      console.error('Error approving user:', error);
      alert('Failed to approve user. Please try again.');
    } finally {
      this.processing = false;
    }
  }

  showRejectDialog(user: PendingUser) {
    this.selectedUser = user;
    this.rejectionReason = '';
    this.showingRejectDialog = true;
  }

  closeRejectDialog() {
    this.showingRejectDialog = false;
    this.selectedUser = null;
    this.rejectionReason = '';
  }

  async confirmReject() {
    if (!this.selectedUser) return;

    this.processing = true;
    try {
      await this.firestoreService.rejectPendingUser(
        this.selectedUser,
        this.adminUsername,
        this.rejectionReason
      );
      alert(`${this.selectedUser.fullName} has been rejected.`);
      this.closeRejectDialog();
      await this.loadPendingUsers();
    } catch (error) {
      console.error('Error rejecting user:', error);
      alert('Failed to reject user. Please try again.');
    } finally {
      this.processing = false;
    }
  }

  formatDate(timestamp: any): string {
    if (!timestamp) return 'N/A';
    
    if (timestamp.toDate) {
      return timestamp.toDate().toLocaleString();
    }
    
    if (timestamp.seconds) {
      return new Date(timestamp.seconds * 1000).toLocaleString();
    }
    
    return new Date(timestamp).toLocaleString();
  }

  getInitials(fullName: string): string {
    if (!fullName) return '?';
    const names = fullName.trim().split(' ');
    if (names.length === 1) {
      return names[0].charAt(0).toUpperCase();
    }
    return (names[0].charAt(0) + names[names.length - 1].charAt(0)).toUpperCase();
  }
}

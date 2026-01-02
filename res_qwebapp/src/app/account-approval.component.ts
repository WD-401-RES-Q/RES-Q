import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { FirestoreService } from './firestore.service';

interface PendingUser {
  id: string;
  username: string;
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
  template: `
    <div class="account-approval-container">
      <h1>Account Approval Management</h1>

      <!-- Tabs -->
      <div class="tabs">
        <button 
          [class.active]="activeTab === 'pending'" 
          (click)="activeTab = 'pending'; loadPendingUsers()">
          Pending ({{ pendingUsers.length }})
        </button>
        <button 
          [class.active]="activeTab === 'approved'" 
          (click)="activeTab = 'approved'; loadApprovedUsers()">
          Approved ({{ approvedUsers.length }})
        </button>
        <button 
          [class.active]="activeTab === 'rejected'" 
          (click)="activeTab = 'rejected'; loadRejectedUsers()">
          Rejected ({{ rejectedUsers.length }})
        </button>
      </div>

      <!-- Pending Users Tab -->
      <div *ngIf="activeTab === 'pending'" class="tab-content">
        <div *ngIf="loading" class="loading">
          <div class="spinner"></div>
          <p>Loading pending accounts...</p>
        </div>
        
        <div *ngIf="!loading && pendingUsers.length === 0" class="empty-state">
          <div class="empty-icon">📋</div>
          <h3>No Pending Accounts</h3>
          <p>There are currently no unverified accounts waiting for approval.</p>
          <p class="info-text">New registrations will appear here for review.</p>
        </div>

        <div *ngIf="!loading && pendingUsers.length > 0" class="users-grid">
          <div *ngFor="let user of pendingUsers" class="user-card unverified">
            <div class="user-header">
              <div class="user-avatar">{{ getInitials(user.fullName) }}</div>
              <div class="user-title">
                <h3>{{ user.fullName }}</h3>
                <span class="username-text">@{{ user.username }}</span>
              </div>
              <span class="status-badge unverified">Unverified</span>
            </div>
            
            <div class="user-details">
              <div class="detail-row">
                <span class="detail-icon">📧</span>
                <div>
                  <strong>Email</strong>
                  <p>{{ user.email }}</p>
                </div>
              </div>
              <div class="detail-row">
                <span class="detail-icon">📱</span>
                <div>
                  <strong>Phone</strong>
                  <p>{{ user.contactNumber }}</p>
                </div>
              </div>
              <div class="detail-row">
                <span class="detail-icon">📍</span>
                <div>
                  <strong>Address</strong>
                  <p>{{ user.address }}</p>
                </div>
              </div>
              <div class="detail-row">
                <span class="detail-icon">🎂</span>
                <div>
                  <strong>Date of Birth</strong>
                  <p>{{ user.dateOfBirth }}</p>
                </div>
              </div>
              <div class="detail-row">
                <span class="detail-icon">⏰</span>
                <div>
                  <strong>Registered</strong>
                  <p>{{ formatDate(user.createdAt) }}</p>
                </div>
              </div>
            </div>

            <div class="user-actions">
              <button 
                class="btn-approve" 
                (click)="approveUser(user)"
                [disabled]="processing">
                <span class="btn-icon">✓</span> Approve Account
              </button>
              <button 
                class="btn-reject" 
                (click)="showRejectDialog(user)"
                [disabled]="processing">
                <span class="btn-icon">✗</span> Reject
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Approved Users Tab -->
      <div *ngIf="activeTab === 'approved'" class="tab-content">
        <div *ngIf="loading" class="loading">Loading...</div>
        
        <div *ngIf="!loading && approvedUsers.length === 0" class="empty-state">
          <p>No approved accounts yet</p>
        </div>

        <div *ngIf="!loading && approvedUsers.length > 0" class="users-list">
          <table>
            <thead>
              <tr>
                <th>Full Name</th>
                <th>Username</th>
                <th>Email</th>
                <th>Phone</th>
                <th>Approved At</th>
                <th>Approved By</th>
              </tr>
            </thead>
            <tbody>
              <tr *ngFor="let user of approvedUsers">
                <td>{{ user.fullName }}</td>
                <td>{{ user.username }}</td>
                <td>{{ user.email }}</td>
                <td>{{ user.contactNumber }}</td>
                <td>{{ formatDate(user['approvedAt']) }}</td>
                <td>{{ user['approvedBy'] || 'N/A' }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Rejected Users Tab -->
      <div *ngIf="activeTab === 'rejected'" class="tab-content">
        <div *ngIf="loading" class="loading">Loading...</div>
        
        <div *ngIf="!loading && rejectedUsers.length === 0" class="empty-state">
          <p>No rejected accounts</p>
        </div>

        <div *ngIf="!loading && rejectedUsers.length > 0" class="users-list">
          <table>
            <thead>
              <tr>
                <th>Full Name</th>
                <th>Username</th>
                <th>Email</th>
                <th>Rejected At</th>
                <th>Rejected By</th>
                <th>Reason</th>
              </tr>
            </thead>
            <tbody>
              <tr *ngFor="let user of rejectedUsers">
                <td>{{ user.fullName }}</td>
                <td>{{ user.username }}</td>
                <td>{{ user.email }}</td>
                <td>{{ formatDate(user['rejectedAt']) }}</td>
                <td>{{ user['rejectedBy'] || 'N/A' }}</td>
                <td>{{ user['rejectionReason'] || 'N/A' }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Reject Dialog -->
      <div *ngIf="showingRejectDialog" class="modal-overlay" (click)="closeRejectDialog()">
        <div class="modal-content" (click)="$event.stopPropagation()">
          <h2>Reject Account</h2>
          <p>Are you sure you want to reject <strong>{{ selectedUser?.fullName }}</strong>?</p>
          
          <div class="form-group">
            <label>Reason for rejection:</label>
            <textarea 
              [(ngModel)]="rejectionReason" 
              rows="4"
              placeholder="Enter reason..."></textarea>
          </div>

          <div class="modal-actions">
            <button class="btn-cancel" (click)="closeRejectDialog()">Cancel</button>
            <button class="btn-confirm-reject" (click)="confirmReject()">Reject Account</button>
          </div>
        </div>
      </div>
    </div>
  `,
  styles: [`
    .account-approval-container {
      padding: 20px;
      max-width: 1400px;
      margin: 0 auto;
    }

    h1 {
      color: #AC1B22;
      margin-bottom: 20px;
    }

    .tabs {
      display: flex;
      gap: 10px;
      margin-bottom: 20px;
      border-bottom: 2px solid #e0e0e0;
    }

    .tabs button {
      padding: 10px 20px;
      border: none;
      background: none;
      cursor: pointer;
      font-size: 16px;
      font-weight: 500;
      color: #666;
      border-bottom: 3px solid transparent;
      transition: all 0.3s;
    }

    .tabs button.active {
      color: #AC1B22;
      border-bottom-color: #AC1B22;
    }

    .loading {
      text-align: center;
      padding: 60px 40px;
      color: #666;
    }

    .spinner {
      width: 50px;
      height: 50px;
      border: 4px solid #f3f3f3;
      border-top: 4px solid #AC1B22;
      border-radius: 50%;
      animation: spin 1s linear infinite;
      margin: 0 auto 20px;
    }

    @keyframes spin {
      0% { transform: rotate(0deg); }
      100% { transform: rotate(360deg); }
    }

    .empty-state {
      text-align: center;
      padding: 60px 40px;
      background: white;
      border-radius: 8px;
      box-shadow: 0 2px 8px rgba(0,0,0,0.1);
    }

    .empty-icon {
      font-size: 64px;
      margin-bottom: 20px;
    }

    .empty-state h3 {
      color: #212121;
      margin: 0 0 10px 0;
      font-size: 24px;
    }

    .empty-state p {
      color: #666;
      margin: 8px 0;
      font-size: 16px;
    }

    .empty-state .info-text {
      color: #999;
      font-size: 14px;
      font-style: italic;
      margin-top: 20px;
    }

    .users-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
      gap: 20px;
    }

    .user-card {
      border: 1px solid #e0e0e0;
      border-radius: 12px;
      padding: 24px;
      background: white;
      box-shadow: 0 2px 8px rgba(0,0,0,0.08);
      transition: all 0.3s ease;
    }

    .user-card:hover {
      box-shadow: 0 4px 16px rgba(0,0,0,0.12);
      transform: translateY(-2px);
    }

    .user-card.unverified {
      border-left: 4px solid #FFC806;
    }

    .user-header {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      margin-bottom: 20px;
      padding-bottom: 20px;
      border-bottom: 2px solid #f5f5f5;
      gap: 15px;
    }

    .user-avatar {
      width: 50px;
      height: 50px;
      border-radius: 50%;
      background: linear-gradient(135deg, #AC1B22, #FFC806);
      color: white;
      display: flex;
      align-items: center;
      justify-content: center;
      font-weight: 700;
      font-size: 20px;
      flex-shrink: 0;
    }

    .user-title {
      flex: 1;
      min-width: 0;
    }

    .user-title h3 {
      margin: 0 0 4px 0;
      color: #212121;
      font-size: 18px;
      font-weight: 600;
    }

    .username-text {
      color: #666;
      font-size: 14px;
      font-weight: 500;
    }

    .status-badge {
      padding: 6px 14px;
      border-radius: 16px;
      font-size: 12px;
      font-weight: 600;
      white-space: nowrap;
      flex-shrink: 0;
    }

    .status-badge.unverified {
      background: #FFF3CD;
      color: #856404;
      border: 1px solid #FFC806;
    }

    .status-badge.pending {
      background: #FFC806;
      color: #212121;
    }

    .user-details {
      display: flex;
      flex-direction: column;
      gap: 12px;
      margin-bottom: 20px;
    }

    .detail-row {
      display: flex;
      gap: 12px;
      align-items: flex-start;
    }

    .detail-icon {
      font-size: 20px;
      flex-shrink: 0;
      margin-top: 2px;
    }

    .detail-row div {
      flex: 1;
      min-width: 0;
    }

    .detail-row strong {
      display: block;
      color: #666;
      font-size: 12px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-bottom: 4px;
    }

    .detail-row p {
      margin: 0;
      font-size: 14px;
      color: #212121;
      word-wrap: break-word;
    }

    .user-actions {
      display: flex;
      gap: 12px;
      margin-top: 20px;
    }

    .btn-approve, .btn-reject {
      flex: 1;
      padding: 12px 20px;
      border: none;
      border-radius: 8px;
      cursor: pointer;
      font-weight: 600;
      font-size: 14px;
      transition: all 0.3s;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
    }

    .btn-icon {
      font-size: 16px;
    }

    .btn-approve {
      background: #00A458;
      color: white;
    }

    .btn-approve:hover:not(:disabled) {
      background: #008a48;
      box-shadow: 0 4px 12px rgba(0, 164, 88, 0.3);
    }

    .btn-reject {
      background: #AC1B22;
      color: white;
    }

    .btn-reject:hover:not(:disabled) {
      background: #8a1519;
      box-shadow: 0 4px 12px rgba(172, 27, 34, 0.3);
    }

    button:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }

    .users-list table {
      width: 100%;
      border-collapse: collapse;
      background: white;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }

    .users-list th,
    .users-list td {
      padding: 12px;
      text-align: left;
      border-bottom: 1px solid #e0e0e0;
    }

    .users-list th {
      background: #f5f5f5;
      font-weight: 600;
      color: #212121;
    }

    .modal-overlay {
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      background: rgba(0,0,0,0.5);
      display: flex;
      align-items: center;
      justify-content: center;
      z-index: 1000;
    }

    .modal-content {
      background: white;
      padding: 30px;
      border-radius: 8px;
      max-width: 500px;
      width: 90%;
    }

    .modal-content h2 {
      margin-top: 0;
      color: #AC1B22;
    }

    .form-group {
      margin: 20px 0;
    }

    .form-group label {
      display: block;
      margin-bottom: 8px;
      font-weight: 500;
    }

    .form-group textarea {
      width: 100%;
      padding: 10px;
      border: 1px solid #e0e0e0;
      border-radius: 4px;
      font-family: inherit;
      resize: vertical;
    }

    .modal-actions {
      display: flex;
      gap: 10px;
      justify-content: flex-end;
    }

    .btn-cancel, .btn-confirm-reject {
      padding: 10px 20px;
      border: none;
      border-radius: 4px;
      cursor: pointer;
      font-weight: 600;
    }

    .btn-cancel {
      background: #e0e0e0;
      color: #212121;
    }

    .btn-confirm-reject {
      background: #AC1B22;
      color: white;
    }
  `]
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

  constructor(private firestoreService: FirestoreService) {}

  ngOnInit() {
    this.loadPendingUsers();
  }

  async loadPendingUsers() {
    this.loading = true;
    try {
      this.pendingUsers = await this.firestoreService.getPendingUsers();
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
      this.approvedUsers = await this.firestoreService.getApprovedUsers();
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

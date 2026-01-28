import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { FirestoreService } from '../../../core/services/firestore.service';
import { FirebaseStorageService } from '../../../core/services/firebase-storage.service';
import { Subscription, Observable } from 'rxjs';

interface UnverifiedAccount {
  id: string;
  fullName: string;
  username: string;
  email: string;
  address: string;
  dateOfBirth: string;
  contactNumber: string;
  idPhotoPath: string;
  createdAt: any;
  accountStatus: string;
}

@Component({
  selector: 'app-unverified-accounts',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './unverified-accounts.html',
  styleUrls: ['./unverified-accounts.component.scss'],
})
export class UnverifiedAccountsComponent implements OnInit, OnDestroy {
  accounts$: Observable<any[]>;
  isLoading$: Observable<boolean>;
  accounts: UnverifiedAccount[] = [];
  adminUsername = 'admin'; // TODO: Get from auth service
  
  // Result Modal state
  showModal = false;
  modalTitle = '';
  modalMessage = '';
  modalType: 'success' | 'error' = 'success';

  // Confirmation Modal state
  showConfirmModal = false;
  confirmAction: 'approve' | 'reject' | null = null;
  selectedAccount: UnverifiedAccount | null = null;
  rejectionReason = '';

  // ID Preview Modal state
  showIdModal = false;
  idModalUrl: string | null = null;

  private subscription?: Subscription;

  constructor(
    private firestoreService: FirestoreService,
    private firebaseStorageService: FirebaseStorageService
  ) {
    console.log('UnverifiedAccountsComponent constructor called');
    // Expose the observables directly for the template
    this.accounts$ = this.firestoreService.pendingUsers$;
    this.isLoading$ = this.firestoreService.isLoading$;
  }

  ngOnInit() {
    console.log('=== UNVERIFIED ACCOUNTS COMPONENT INIT ===');
    console.log('Component instance created at:', new Date().toISOString());
    
    // Subscribe to update local array
    this.subscription = this.accounts$.subscribe(
      (users) => {
        console.log('=== PENDING USERS DATA RECEIVED IN COMPONENT ===');
        console.log('Users count:', users.length);
        
        this.accounts = users as UnverifiedAccount[];
        console.log('Component accounts array updated:', this.accounts.length);
      },
      (error) => {
        console.error('=== ERROR IN PENDING USERS SUBSCRIPTION ===', error);
      }
    );
    
    console.log('Subscription to pendingUsers$ established');
  }

  ngOnDestroy() {
    console.log('UnverifiedAccountsComponent ngOnDestroy called');
    if (this.subscription) {
      this.subscription.unsubscribe();
    }
  }

  openApproveConfirm(acc: UnverifiedAccount) {
    this.selectedAccount = acc;
    this.confirmAction = 'approve';
    this.showConfirmModal = true;
  }

  openRejectConfirm(acc: UnverifiedAccount) {
    this.selectedAccount = acc;
    this.confirmAction = 'reject';
    this.rejectionReason = '';
    this.showConfirmModal = true;
  }

  closeConfirmModal() {
    this.showConfirmModal = false;
    this.selectedAccount = null;
    this.confirmAction = null;
    this.rejectionReason = '';
  }

  async confirmApprove() {
    if (!this.selectedAccount) return;

    const accountName = this.selectedAccount.fullName;
    
    try {
      await this.firestoreService.approvePendingUser(this.selectedAccount, this.adminUsername);
      this.closeConfirmModal();
      this.showModalMessage('Success', `${accountName} has been approved successfully!`, 'success');
    } catch (error: any) {
      this.closeConfirmModal();
      this.showModalMessage('Approval Failed', `Error: ${error.message || 'Unknown error occurred'}`, 'error');
    }
  }

  async confirmReject() {
    if (!this.selectedAccount || !this.rejectionReason.trim()) {
      return;
    }

    const accountName = this.selectedAccount.fullName;
    
    try {
      await this.firestoreService.rejectPendingUser(this.selectedAccount, this.adminUsername, this.rejectionReason);
      this.closeConfirmModal();
      this.showModalMessage('Rejected', `${accountName} has been rejected.`, 'success');
    } catch (error: any) {
      this.closeConfirmModal();
      this.showModalMessage('Rejection Failed', `Error: ${error.message || 'Unknown error occurred'}`, 'error');
    }
  }

  showModalMessage(title: string, message: string, type: 'success' | 'error') {
    this.modalTitle = title;
    this.modalMessage = message;
    this.modalType = type;
    this.showModal = true;
  }

  closeModal() {
    this.showModal = false;
  }

  // Get the ID photo URL from storage path
  getIdPhotoUrl(account: UnverifiedAccount): string | null {
    // Check multiple possible field names for ID photo
    const path = (account.idPhotoPath || (account as any).idPhoto || (account as any).validIdUrl || '').trim();
    if (!path) {
      return null;
    }
    if (path.startsWith('http')) {
      return path;
    }
    return this.firebaseStorageService.getDownloadUrl(path);
  }

  openIdModal(account: UnverifiedAccount) {
    const url = this.getIdPhotoUrl(account);
    if (!url) {
      return;
    }
    this.idModalUrl = url;
    this.showIdModal = true;
  }

  closeIdModal() {
    this.showIdModal = false;
    this.idModalUrl = null;
  }
}

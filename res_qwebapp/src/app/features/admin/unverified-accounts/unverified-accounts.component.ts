import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { FirestoreService } from '../../../core/services/firestore.service';
import { FirebaseStorageService } from '../../../core/services/firebase-storage.service';
import { EmailService } from '../../../core/services/email.service';
import { Subscription, Observable } from 'rxjs';

interface UnverifiedAccount {
  id: string;
  fullName?: string;
  email?: string;
  address?: string;
  dateOfBirth?: string;
  contactNumber?: string;
  idPhotoPath?: string;
  idPhotoFront?: string;
  idPhotoSelfie?: string;
  createdAt: any;
  accountStatus?: string;
  [key: string]: any;
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
  readonly pageSize = 10;
  currentPage = 1;
  processing = false;
  adminUsername = 'admin'; // TODO: Get from auth service
  
  // Non-blocking status banner state
  showStatusBanner = false;
  statusMessage = '';
  statusType: 'success' | 'error' = 'success';

  // Confirmation Modal state
  showConfirmModal = false;
  confirmAction: 'approve' | 'reject' | null = null;
  selectedAccount: UnverifiedAccount | null = null;
  rejectionReason = '';

  // ID Preview Modal state
  showIdModal = false;
  idModalTitle = 'VALID ID';
  idModalUrl: string | null = null;

  // Result Modal state
  showResultModal = false;
  resultTitle = '';
  resultMessage = '';
  resultType: 'success' | 'error' = 'success';

  private subscription?: Subscription;
  private statusBannerTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(
    private firestoreService: FirestoreService,
    private firebaseStorageService: FirebaseStorageService,
    private emailService: EmailService
  ) {
    // Expose the observables directly for the template
    this.accounts$ = this.firestoreService.pendingUsers$;
    this.isLoading$ = this.firestoreService.isLoading$;
  }

  ngOnInit() {
    
    // Subscribe to update local array
    this.subscription = this.accounts$.subscribe(
      (users) => {

        this.accounts = (users as any[]).map((raw) => this.mapAccount(raw));
        this.ensureCurrentPageInBounds();
      },
      (error) => {
        console.error('=== ERROR IN PENDING USERS SUBSCRIPTION ===', error);
      }
    );
    
  }

  ngOnDestroy() {
    if (this.subscription) {
      this.subscription.unsubscribe();
    }
    if (this.statusBannerTimer) {
      clearTimeout(this.statusBannerTimer);
      this.statusBannerTimer = null;
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
    if (!this.selectedAccount || this.processing) return;

    const account = this.selectedAccount;
    const accountName = (account.fullName || 'User').trim();
    const accountEmail = (account.email || '').trim();

    this.processing = true;
    // Close confirmation immediately to prevent a stuck "Approving..." modal.
    this.closeConfirmModal();
    try {
      await this.firestoreService.approvePendingUser(account, this.adminUsername);

      this.removeAccountFromLocalCache(account.id);
      this.showResult(
        'Account Approved',
        `${accountName} has been approved successfully.`,
        'success'
      );

      // Do not block success UI on email delivery.
      this.sendApprovalEmailInBackground(accountEmail, accountName);
    } catch (error: any) {
      this.showResult(
        'Approval Failed',
        `Approval failed: ${error.message || 'Unknown error occurred'}`,
        'error'
      );
    } finally {
      this.processing = false;
    }
  }

  async confirmReject() {
    if (!this.selectedAccount || !this.rejectionReason.trim() || this.processing) {
      return;
    }

    const account = this.selectedAccount;
    const rejectionReason = this.rejectionReason.trim();
    const accountName = (account.fullName || 'User').trim();
    const accountEmail = (account.email || '').trim();

    this.processing = true;
    // Close confirmation immediately to prevent a stuck "Rejecting..." modal.
    this.closeConfirmModal();
    try {
      await this.firestoreService.rejectPendingUser(account, rejectionReason);

      this.removeAccountFromLocalCache(account.id);
      this.showResult(
        'Account Rejected',
        `${accountName} has been rejected.`,
        'success'
      );

      // Do not block success UI on email delivery.
      this.sendRejectionEmailInBackground(
        accountEmail,
        accountName,
        rejectionReason
      );
    } catch (error: any) {
      this.showResult(
        'Rejection Failed',
        `Rejection failed: ${error.message || 'Unknown error occurred'}`,
        'error'
      );
    } finally {
      this.processing = false;
    }
  }

  closeResultModal(): void {
    this.showResultModal = false;
  }

  private showStatusMessage(message: string, type: 'success' | 'error') {
    this.statusMessage = message;
    this.statusType = type;
    this.showStatusBanner = true;

    if (this.statusBannerTimer) {
      clearTimeout(this.statusBannerTimer);
    }

    this.statusBannerTimer = setTimeout(() => {
      this.showStatusBanner = false;
      this.statusBannerTimer = null;
    }, 3200);
  }

  // Get the ID photo URL from storage path
  getIdPhotoUrl(account: UnverifiedAccount): string | null {
    const path = (
      account.idPhotoPath ||
      account.idPhotoFront ||
      (account as any).idPhoto ||
      (account as any).validIdUrl ||
      ''
    ).trim();
    if (!path) {
      return null;
    }
    if (path.startsWith('http')) {
      return path;
    }
    return this.firebaseStorageService.getDownloadUrl(path);
  }

  private showResult(
    title: string,
    message: string,
    type: 'success' | 'error'
  ): void {
    this.resultTitle = title;
    this.resultMessage = message;
    this.resultType = type;
    this.showResultModal = true;
  }

  private sendApprovalEmailInBackground(
    accountEmail: string,
    accountName: string
  ): void {
    if (!accountEmail) {
      return;
    }
    void this.emailService
      .sendApprovalEmail(accountEmail, accountName)
      .then((emailSent) => {
        if (!emailSent) {
          console.warn(
            'Failed to send approval email, but account was approved'
          );
        }
      })
      .catch((error) => {
        console.warn('Approval email failed:', error);
      });
  }

  private sendRejectionEmailInBackground(
    accountEmail: string,
    accountName: string,
    rejectionReason: string
  ): void {
    if (!accountEmail) {
      return;
    }
    void this.emailService
      .sendRejectionEmail(accountEmail, accountName, rejectionReason)
      .then((emailSent) => {
        if (!emailSent) {
          console.warn(
            'Failed to send rejection email, but account was rejected'
          );
        }
      })
      .catch((error) => {
        console.warn('Rejection email failed:', error);
      });
  }

  // Get selfie with ID URL from storage path
  getSelfieWithIdUrl(account: UnverifiedAccount): string | null {
    const path = (
      account.idPhotoSelfie ||
      (account as any).selfieWithId ||
      (account as any).selfieWithIdUrl ||
      ''
    ).trim();
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
    this.idModalTitle = 'VALID ID';
    this.idModalUrl = url;
    this.showIdModal = true;
  }

  openSelfieWithIdModal(account: UnverifiedAccount) {
    const url = this.getSelfieWithIdUrl(account);
    if (!url) {
      return;
    }
    this.idModalTitle = 'SELFIE WITH ID';
    this.idModalUrl = url;
    this.showIdModal = true;
  }

  closeIdModal() {
    this.showIdModal = false;
    this.idModalUrl = null;
  }

  get paginatedAccounts(): UnverifiedAccount[] {
    const start = (this.currentPage - 1) * this.pageSize;
    return this.accounts.slice(start, start + this.pageSize);
  }

  get totalPages(): number {
    return Math.max(1, Math.ceil(this.accounts.length / this.pageSize));
  }

  get startItem(): number {
    if (this.accounts.length === 0) {
      return 0;
    }
    return (this.currentPage - 1) * this.pageSize + 1;
  }

  get endItem(): number {
    return Math.min(this.currentPage * this.pageSize, this.accounts.length);
  }

  get canGoPrevious(): boolean {
    return this.currentPage > 1;
  }

  get canGoNext(): boolean {
    return this.currentPage < this.totalPages;
  }

  previousPage(): void {
    if (!this.canGoPrevious) {
      return;
    }
    this.currentPage -= 1;
  }

  nextPage(): void {
    if (!this.canGoNext) {
      return;
    }
    this.currentPage += 1;
  }

  private mapAccount(raw: any): UnverifiedAccount {
    return {
      id: typeof raw?.id === 'string' ? raw.id : '',
      fullName: typeof raw?.fullName === 'string' ? raw.fullName : '',
      email: typeof raw?.email === 'string' ? raw.email : '',
      address: typeof raw?.address === 'string' ? raw.address : '',
      dateOfBirth: typeof raw?.dateOfBirth === 'string' ? raw.dateOfBirth : '',
      contactNumber: typeof raw?.contactNumber === 'string' ? raw.contactNumber : '',
      idPhotoPath: typeof raw?.idPhotoPath === 'string' ? raw.idPhotoPath : '',
      idPhotoFront: typeof raw?.idPhotoFront === 'string' ? raw.idPhotoFront : '',
      idPhotoSelfie: typeof raw?.idPhotoSelfie === 'string' ? raw.idPhotoSelfie : '',
      createdAt: raw?.createdAt ?? null,
      accountStatus: typeof raw?.accountStatus === 'string' ? raw.accountStatus : '',
    };
  }

  private removeAccountFromLocalCache(accountId: string): void {
    this.accounts = this.accounts.filter((account) => account.id !== accountId);
    this.ensureCurrentPageInBounds();
  }

  private ensureCurrentPageInBounds(): void {
    if (this.currentPage < 1) {
      this.currentPage = 1;
      return;
    }
    const maxPage = this.totalPages;
    if (this.currentPage > maxPage) {
      this.currentPage = maxPage;
    }
  }
}

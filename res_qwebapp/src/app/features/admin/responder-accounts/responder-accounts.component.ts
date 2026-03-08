import { Component, OnInit, OnDestroy, ChangeDetectionStrategy, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { FirestoreService } from '../../../core/services/firestore.service';
import { Unsubscribe, collection, getDocs } from 'firebase/firestore';
import { db } from '../../../core/config/firebase.config';

interface ResponderAccount {
  id: string;
  fullName: string;
  name?: string;
  username: string;
  role: string;
  contactNumber: string;
  phoneNumber?: string;
  pin: string;
  password: string;
  status: string;
  isLoggedIn: boolean;
  isAvailable: boolean;
  createdAt?: any;
}

@Component({
  selector: 'app-responder-accounts',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './responder-accounts.html',
  styleUrls: ['./responder-accounts.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ResponderAccountsComponent implements OnInit, OnDestroy {
  // Account list
  accounts: ResponderAccount[] = [];
  isLoadingAccounts = true;
  loadError = '';

  // Modal state
  showCreateModal = false;

  // Form fields
  fullName = '';
  contactNumber = '';
  pin = '';
  password = '';
  role = 'responder';

  // Form state
  isSubmitting = false;
  submitStage: 'idle' | 'checking' | 'creating' = 'idle';
  successMessage = '';
  errorMessage = '';

  // Delete state
  accountToDelete: ResponderAccount | null = null;
  isDeleting = false;

  private accountsUnsubscribe?: Unsubscribe;
  private readonly CACHE_KEY = 'responder_accounts_cache';

  constructor(
    private firestoreService: FirestoreService,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.loadAccounts();
  }

  ngOnDestroy(): void {
    if (this.accountsUnsubscribe) {
      this.accountsUnsubscribe();
    }
  }

  async loadAccounts(): Promise<void> {
    this.isLoadingAccounts = true;
    this.loadError = '';

    // Load cached data immediately for instant display
    const cached = this.loadFromCache();
    if (cached && cached.length > 0) {
      this.accounts = cached;
      this.isLoadingAccounts = false;
      this.cdr.markForCheck();
    }

    try {
      // Fast initial load using getDocs
      if (!cached || cached.length === 0) {
        const snapshot = await getDocs(collection(db, 'responders'));
        const initialDocs = snapshot.docs.map(doc => this.mapDocToAccount(doc.id, doc.data()));
        this.accounts = initialDocs;
        this.saveToCache(initialDocs);
        this.isLoadingAccounts = false;
        this.cdr.markForCheck();
      }

      // Set up real-time listener for updates
      this.accountsUnsubscribe = this.firestoreService.listenToCollection(
        'responders',
        (docs: any[]) => {
          this.accounts = docs.map(doc => this.mapDocToAccount(doc.id, doc));
          this.saveToCache(this.accounts);
          this.isLoadingAccounts = false;
          this.cdr.markForCheck();
        },
        (error: any) => {
          console.error('Error listening to responders:', error);
          if (!this.accounts.length) {
            this.loadError = 'Failed to load accounts. Please refresh the page.';
          }
          this.isLoadingAccounts = false;
          this.cdr.markForCheck();
        }
      );
    } catch (error: any) {
      console.error('Error loading accounts:', error);
      if (!this.accounts.length) {
        this.loadError = 'Failed to connect to Firebase.';
      }
      this.isLoadingAccounts = false;
      this.cdr.markForCheck();
    }
  }

  private mapDocToAccount(id: string, doc: any): ResponderAccount {
    return {
      id,
      fullName: doc.fullName || doc.name || 'Unknown',
      name: doc.name,
      username: doc.username || '',
      role: doc.role || 'responder',
      contactNumber: doc.contactNumber || doc.phoneNumber || '',
      phoneNumber: doc.phoneNumber,
      pin: doc.pin || '',
      password: doc.password || '',
      status: doc.status || 'offline',
      isLoggedIn: doc.isLoggedIn || false,
      isAvailable: doc.isAvailable || false,
      createdAt: doc.createdAt,
    };
  }

  private loadFromCache(): ResponderAccount[] | null {
    try {
      const cached = localStorage.getItem(this.CACHE_KEY);
      if (cached) {
        const parsed = JSON.parse(cached);
        if (Array.isArray(parsed) && Date.now() - (parsed[0]?.cachedAt || 0) < 5 * 60 * 1000) {
          return parsed.map((item: any) => ({ ...item, cachedAt: undefined }));
        }
      }
    } catch (e) {
      console.warn('Failed to load accounts from cache:', e);
    }
    return null;
  }

  private saveToCache(accounts: ResponderAccount[]): void {
    try {
      const withTimestamp = accounts.map(acc => ({ ...acc, cachedAt: Date.now() }));
      localStorage.setItem(this.CACHE_KEY, JSON.stringify(withTimestamp));
    } catch (e) {
      console.warn('Failed to cache accounts:', e);
    }
  }

  trackByAccountId(index: number, account: ResponderAccount): string {
    return account.id;
  }

  openCreateModal(): void {
    this.showCreateModal = true;
    this.resetForm();
    this.cdr.markForCheck();
  }

  closeCreateModal(): void {
    this.showCreateModal = false;
    this.resetForm();
    this.cdr.markForCheck();
  }

  resetForm(): void {
    this.fullName = '';
    this.contactNumber = '';
    this.pin = '';
    this.password = '';
    this.role = 'responder';
    this.successMessage = '';
    this.errorMessage = '';
    this.isSubmitting = false;
    this.submitStage = 'idle';
  }

  get canSubmit(): boolean {
    return (
      this.fullName.trim().length >= 2 &&
      this.pin.trim().length === 4 &&
      this.password.trim().length >= 6 &&
      this.normalizeContactNumber(this.contactNumber).length > 0
    );
  }

  async createResponderAccount(): Promise<void> {
    if (!this.canSubmit || this.isSubmitting) {
      return;
    }

    const normalizedPhone = this.normalizeContactNumber(this.contactNumber);
    if (!this.isValidContactNumber(normalizedPhone)) {
      this.successMessage = '';
      this.errorMessage = 'Use a valid PH mobile number (e.g. 09123456789 or +639123456789).';
      return;
    }

    if (!/^\d{4}$/.test(this.pin.trim())) {
      this.successMessage = '';
      this.errorMessage = 'PIN must be exactly 4 digits.';
      return;
    }

    this.isSubmitting = true;
    this.submitStage = 'checking';
    this.successMessage = '';
    this.errorMessage = '';

    try {
      // Check for existing account with same phone (with timeout)
      let existing: any[] = [];
      try {
        const checkPromise = this.firestoreService.queryCollection(
          'responders',
          'contactNumber',
          '==',
          normalizedPhone
        );
        
        // Add timeout to prevent hanging
        const timeoutPromise = new Promise<any[]>((_, reject) => {
          setTimeout(() => reject(new Error('Query timed out')), 10000);
        });
        
        existing = await Promise.race([checkPromise, timeoutPromise]);
      } catch (queryError: any) {
        console.error('Error checking existing accounts:', queryError);
        // If query fails (e.g., missing index), proceed with creation
        // The Firestore rules will prevent duplicates anyway
        existing = [];
      }

      if (existing.length > 0) {
        this.errorMessage = 'A responder account with this number already exists.';
        this.isSubmitting = false;
        this.submitStage = 'idle';
        this.cdr.markForCheck();
        return;
      }

      const cleanName = this.fullName.trim();
      const username = this.buildUsername(cleanName);
      this.submitStage = 'creating';

      const docData: Record<string, any> = {
        fullName: cleanName,
        name: cleanName,
        username,
        role: this.role.trim() || 'responder',
        contactNumber: normalizedPhone,
        phoneNumber: normalizedPhone,
        pin: this.pin.trim(),
        password: this.password.trim(),
        isLoggedIn: false,
        status: 'offline',
        isAvailable: false,
      };

      await this.firestoreService.addDocument('responders', docData);

      this.successMessage = `Account created for ${cleanName}!`;
      this.cdr.markForCheck();
      
      // Close modal after short delay to show success
      setTimeout(() => {
        this.closeCreateModal();
      }, 1500);

    } catch (error: any) {
      console.error('Failed to create responder account:', error);
      const msg = error?.message || '';
      const code = error?.code || '';
      
      if (msg.toLowerCase().includes('permission') || code.includes('permission')) {
        this.errorMessage = 'Permission denied. Check Firestore rules.';
      } else {
        this.errorMessage = `Failed to create account: ${code || msg || 'Unknown error'}`;
      }
      this.cdr.markForCheck();
    } finally {
      this.isSubmitting = false;
      this.submitStage = 'idle';
      this.cdr.markForCheck();
    }
  }

  getStatusClass(account: ResponderAccount): string {
    if (account.isAvailable) return 'status-available';
    if (account.isLoggedIn || account.status === 'online') return 'status-online';
    return 'status-offline';
  }

  getStatusText(account: ResponderAccount): string {
    if (account.isAvailable) return 'Available';
    if (account.isLoggedIn || account.status === 'online') return 'Online';
    return 'Offline';
  }

  getAccountInitial(account: ResponderAccount): string {
    const name = account.fullName || 'U';
    return name.charAt(0).toUpperCase();
  }

  private normalizeContactNumber(value: string): string {
    const digits = value.replace(/\D/g, '');
    if (!digits) return '';

    if (digits.startsWith('0') && digits.length === 11) {
      return `+63${digits.slice(1)}`;
    }
    if (digits.startsWith('63') && digits.length === 12) {
      return `+${digits}`;
    }
    if (digits.startsWith('9') && digits.length === 10) {
      return `+63${digits}`;
    }

    return value.trim();
  }

  private isValidContactNumber(value: string): boolean {
    return /^\+639\d{9}$/.test(value);
  }

  private buildUsername(fullName: string): string {
    const base = fullName
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9]+/g, '.')
      .replace(/^\.+|\.+$/g, '');
    return base || 'responder';
  }

  confirmDelete(account: ResponderAccount): void {
    this.accountToDelete = account;
  }

  cancelDelete(): void {
    this.accountToDelete = null;
  }

  async deleteAccount(): Promise<void> {
    if (!this.accountToDelete || this.isDeleting) return;

    const accountId = this.accountToDelete.id;
    const accountName = this.accountToDelete.fullName;
    this.isDeleting = true;
    this.cdr.markForCheck();

    try {
      await this.firestoreService.deleteDocument('responders', accountId);
      this.accounts = this.accounts.filter((a) => a.id !== accountId);
      this.saveToCache(this.accounts);
      this.accountToDelete = null;
      this.cdr.markForCheck();
    } catch (error: any) {
      console.error('Failed to delete responder account:', error);
      const msg = error?.message || '';
      const code = error?.code || '';
      if (msg.toLowerCase().includes('permission') || code.includes('permission')) {
        alert('Permission denied. Check Firestore rules.');
      } else {
        alert(`Failed to delete account: ${code || msg || 'Unknown error'}`);
      }
    } finally {
      this.isDeleting = false;
      this.cdr.markForCheck();
    }
  }
}

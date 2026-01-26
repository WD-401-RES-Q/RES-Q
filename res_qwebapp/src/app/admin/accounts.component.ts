import { Component, OnInit, OnDestroy, NgZone, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { FirestoreService } from '../firestore.service';
import { FirebaseStorageService } from '../firebase-storage.service';
import { Subscription, Observable } from 'rxjs';

interface Account {
  id: string;
  fullName: string;
  username: string;
  email: string;
  address: string;
  dateOfBirth: string;
  contactNumber: string;
  idPhotoPath: string;
  accountStatus: string;
  approvedAt?: any;
  approvedBy?: string;
  bannedUntil?: any;
}

interface BanReason {
  id: string;
  label: string;
  checked: boolean;
}

@Component({
  selector: 'app-accounts',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './accounts.html',
})
export class AccountsComponent implements OnInit, OnDestroy {
  accounts$: Observable<any[]>;
  isLoading$: Observable<boolean>;
  accounts: Account[] = [];
  filteredAccounts: Account[] = [];
  selected: Account | null = null;
  searchQuery: string = '';
  showBanModal = false;
  showBanReasonsModal = false;
  showBanConfirmationModal = false;
  showUnbanConfirmationModal = false;
  accountToBan: Account | null = null;
  accountToUnban: Account | null = null;
  showIdModal = false;
  idModalUrl: string | null = null;
  banDuration: 'permanent' | '7days' | null = null;
  banDurationText: string = '';
  selectedBanReasons: string[] = [];
  isProcessingBan: boolean = false;
  isProcessingUnban: boolean = false;
  banReasons: BanReason[] = [
    { id: 'false-report', label: 'False Report', checked: false },
    { id: 'vulgar-comments', label: 'Vulgar Comments', checked: false },
    { id: 'false-validation', label: 'False Validation', checked: false },
  ];
  private subscription?: Subscription;

  constructor(
    private firestoreService: FirestoreService,
    private firebaseStorageService: FirebaseStorageService,
    private ngZone: NgZone,
    private cdr: ChangeDetectorRef
  ) {
    console.log('AccountsComponent constructor called');
    // Expose the observables directly
    this.accounts$ = this.firestoreService.approvedUsers$;
    this.isLoading$ = this.firestoreService.isLoading$;
  }

  ngOnInit() {
    console.log('=== ACCOUNTS COMPONENT INIT ===');
    console.log('Component instance created at:', new Date().toISOString());
    
    // Subscribe only to handle selection logic
    this.subscription = this.accounts$.subscribe(
      (users) => {
        console.log('=== APPROVED USERS DATA RECEIVED IN COMPONENT ===');
        console.log('Users count:', users.length);
        
        this.accounts = users as Account[];
        this.filterAccounts();
        
        // Select first account if none selected
        if (this.filteredAccounts.length > 0 && !this.selected) {
          this.selected = this.filteredAccounts[0];
          console.log('Auto-selected first account:', this.selected?.fullName);
        }
        
        // Clear selection if selected account no longer exists
        if (this.selected && !this.filteredAccounts.find(acc => acc.id === this.selected!.id)) {
          this.selected = this.filteredAccounts.length > 0 ? this.filteredAccounts[0] : null;
          console.log('Selection updated');
        }
      },
      (error) => {
        console.error('=== ERROR IN APPROVED USERS SUBSCRIPTION ===', error);
      }
    );
    
    console.log('Subscription to approvedUsers$ established');
  }

  filterAccounts() {
    if (!this.searchQuery.trim()) {
      this.filteredAccounts = this.accounts;
    } else {
      const query = this.searchQuery.toLowerCase();
      this.filteredAccounts = this.accounts.filter(acc => 
        (acc.fullName?.toLowerCase().includes(query) || false) ||
        (acc.username?.toLowerCase().includes(query) || false) ||
        (acc.email?.toLowerCase().includes(query) || false) ||
        (acc.contactNumber?.toLowerCase().includes(query) || false) ||
        (acc.address?.toLowerCase().includes(query) || false)
      );
    }
    console.log('Filtered accounts:', this.filteredAccounts.length, 'Search query:', this.searchQuery);
  }

  onSearchChange() {
    this.filterAccounts();
    // Reset selection if current selection is not in filtered list
    if (this.selected && !this.filteredAccounts.find(acc => acc.id === this.selected!.id)) {
      this.selected = this.filteredAccounts.length > 0 ? this.filteredAccounts[0] : null;
    }
  }

  ngOnDestroy() {
    console.log('AccountsComponent ngOnDestroy called');
    if (this.subscription) {
      this.subscription.unsubscribe();
    }
  }

  select(account: Account) {
    this.selected = account;
  }

  getApprovedDate(account: Account): Date | null {
    if (!account.approvedAt) return null;
    // Handle both Firestore Timestamp and already converted Date
    if (account.approvedAt.toDate) {
      return account.approvedAt.toDate();
    }
    if (account.approvedAt instanceof Date) {
      return account.approvedAt;
    }
    return null;
  }

  ban(account: Account) {
    this.accountToBan = account;
    this.resetBanReasons();
    this.showBanReasonsModal = true;
  }

  openUnbanConfirmation(account: Account) {
    console.log('=== OPEN UNBAN CONFIRMATION ===', account.fullName);
    this.accountToUnban = account;
    this.showUnbanConfirmationModal = true;
    console.log('showUnbanConfirmationModal set to true');
  }

  cancelUnban() {
    this.showUnbanConfirmationModal = false;
    this.accountToUnban = null;
  }

  async confirmUnban() {
    console.log('=== CONFIRM UNBAN CALLED ===');
    if (!this.accountToUnban || this.isProcessingUnban) {
      console.log('Early return: accountToUnban=', this.accountToUnban, 'isProcessingUnban=', this.isProcessingUnban);
      return;
    }
    
    const accountId = this.accountToUnban.id;
    this.isProcessingUnban = true;
    console.log('Starting unban for:', this.accountToUnban.fullName);
    
    try {
      await this.firestoreService.updateDocument('approved_users', accountId, {
        accountStatus: 'approved',
        bannedUntil: null,
        banReasons: [],
        bannedAt: null,
      });
      console.log('Unban successful, closing modal now');
      
      this.ngZone.run(() => {
        this.showUnbanConfirmationModal = false;
        this.accountToUnban = null;
        this.isProcessingUnban = false;
        this.cdr.markForCheck();
        console.log('Modal state updated and marked for check');
      });
    } catch (error) {
      console.error('Error unbanning account:', error);
      this.isProcessingUnban = false;
    }
  }

  resetBanReasons() {
    this.banReasons.forEach(reason => reason.checked = false);
  }

  cancelBan() {
    this.showBanReasonsModal = false;
    this.accountToBan = null;
    this.banDuration = null;
    this.resetBanReasons();
  }

  async confirmBan(duration: 'permanent' | '7days') {
    if (!this.accountToBan) return;
    
    const selectedReasons = this.banReasons.filter(r => r.checked).map(r => r.label);
    if (selectedReasons.length === 0) {
      alert('Please select at least one reason for banning.');
      return;
    }
    
    this.banDuration = duration;
    this.selectedBanReasons = selectedReasons;
    
    let banUntil: Date | null = null;
    
    if (duration === 'permanent') {
      this.banDurationText = 'PERMANENT BAN';
    } else {
      banUntil = new Date();
      banUntil.setDate(banUntil.getDate() + 7);
      this.banDurationText = `Banned until ${banUntil.toLocaleString()}`;
    }
    
    // Show confirmation modal
    this.showBanReasonsModal = false;
    this.showBanConfirmationModal = true;
  }

  async finalConfirmBan() {
    console.log('=== FINAL CONFIRM BAN CALLED ===');
    console.log('isProcessingBan:', this.isProcessingBan);
    console.log('accountToBan:', this.accountToBan);
    
    if (this.isProcessingBan) {
      console.log('Already processing ban, ignoring duplicate call');
      return;
    }
    
    if (!this.accountToBan) {
      console.log('No account to ban, returning');
      return;
    }
    
    this.isProcessingBan = true;
    console.log('selectedBanReasons:', this.selectedBanReasons);
    console.log('banDuration:', this.banDuration);
    
    let banUntil: Date | null = null;
    
    if (this.banDuration === 'permanent') {
      banUntil = null;
    } else {
      banUntil = new Date();
      banUntil.setDate(banUntil.getDate() + 7);
    }
    
    try {
      const updateData: any = {
        accountStatus: 'BANNED',
        banReasons: this.selectedBanReasons,
        bannedAt: new Date()
      };
      
      if (banUntil) {
        updateData.bannedUntil = banUntil;
      } else {
        updateData.bannedUntil = null;
      }
      
      console.log('Updating Firestore with data:', updateData);
      await this.firestoreService.updateDocument('approved_users', this.accountToBan.id, updateData);
      console.log('Ban successful, closing modal now');
      
      this.ngZone.run(() => {
        this.showBanConfirmationModal = false;
        this.accountToBan = null;
        this.banDuration = null;
        this.selectedBanReasons = [];
        this.resetBanReasons();
        this.isProcessingBan = false;
        this.cdr.markForCheck();
        console.log('Modal state updated and marked for check');
      });
    } catch (error) {
      console.error('Error banning account:', error);
      this.isProcessingBan = false;
    }
  }

  cancelBanConfirmation() {
    this.showBanConfirmationModal = false;
    this.showBanReasonsModal = true;
  }

  openIdModal(account: Account) {
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

  trackById(_: number, acc: Account) {
    return acc.id;
  }

  getIdPhotoUrl(account: Account): string | null {
    const path = (account.idPhotoPath || '').trim();
    if (!path) {
      return null;
    }
    if (path.startsWith('http')) {
      return path;
    }
    return this.firebaseStorageService.getDownloadUrl(path);
  }
}

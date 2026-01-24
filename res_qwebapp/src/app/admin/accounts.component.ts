import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
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
}

@Component({
  selector: 'app-accounts',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './accounts.html',
})
export class AccountsComponent implements OnInit, OnDestroy {
  accounts$: Observable<any[]>;
  isLoading$: Observable<boolean>;
  accounts: Account[] = [];
  selected: Account | null = null;
  showBanModal = false;
  accountToBan: Account | null = null;
  showIdModal = false;
  idModalUrl: string | null = null;
  private subscription?: Subscription;

  constructor(
    private firestoreService: FirestoreService,
    private firebaseStorageService: FirebaseStorageService
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
        
        // Select first account if none selected
        if (this.accounts.length > 0 && !this.selected) {
          this.selected = this.accounts[0];
          console.log('Auto-selected first account:', this.selected?.fullName);
        }
        
        // Clear selection if selected account no longer exists
        if (this.selected && !this.accounts.find(acc => acc.id === this.selected!.id)) {
          this.selected = this.accounts.length > 0 ? this.accounts[0] : null;
          console.log('Selection updated');
        }
      },
      (error) => {
        console.error('=== ERROR IN APPROVED USERS SUBSCRIPTION ===', error);
      }
    );
    
    console.log('Subscription to approvedUsers$ established');
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
    this.showBanModal = true;
  }

  cancelBan() {
    this.showBanModal = false;
    this.accountToBan = null;
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

  async confirmBan() {
    if (!this.accountToBan) return;
    
    console.log('Ban account', this.accountToBan);
    // TODO: Implement ban functionality
    
    this.showBanModal = false;
    this.accountToBan = null;
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

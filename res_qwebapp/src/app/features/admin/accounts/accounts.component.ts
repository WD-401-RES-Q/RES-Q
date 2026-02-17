import { Component, OnInit, OnDestroy, NgZone, ChangeDetectorRef, ElementRef, ViewChild } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { FirestoreService } from '../../../core/services/firestore.service';
import { FirebaseStorageService } from '../../../core/services/firebase-storage.service';
import { AuthService } from '../../../core/services/auth.service';
import { Subscription, Observable } from 'rxjs';

interface Account {
  id: string;
  fullName?: string;
  email: string;
  address: string;
  dateOfBirth: string;
  contactNumber: string;
  idPhotoPath: string;
  idPhotoFront?: string;
  idPhotoSelfie?: string;
  profilePhotoUrl?: string;
  profilePictureUrl?: string;
  profileImageUrl?: string;
  photoUrl?: string;
  avatarUrl?: string;
  accountStatus: string;
  approvedAt?: any;
  approvedBy?: string;
  bannedAt?: any;
  bannedUntil?: any;
  banType?: string;
  isPermanent?: boolean;
  banReasons?: string[];
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
  styleUrls: ['./accounts.component.scss'],
})
export class AccountsComponent implements OnInit, OnDestroy {
  @ViewChild('adminPasswordField') adminPasswordField?: ElementRef<HTMLInputElement>;
  accounts$: Observable<any[]>;
  isLoading$: Observable<boolean>;
  accounts: Account[] = [];
  encryptedAccounts: Account[] = [];
  filteredAccounts: Account[] = [];
  readonly cardsPerPage = 6;
  currentPage = 1;
  searchQuery: string = '';
  accountStatusFilter:
    | 'active'
    | 'all'
    | 'banned'
    | 'temporary'
    | 'permanent' = 'active';
  showBanReasonsModal = false;
  showBanConfirmationModal = false;
  showUnbanConfirmationModal = false;
  accountToBan: Account | null = null;
  accountToUnban: Account | null = null;
  showIdModal = false;
  idModalTitle = 'VALID ID';
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
  showPasswordModal = false;
  adminPasswordInput = '';
  passwordError = '';
  isVerifyingPassword = false;
  private pendingUnlockAccountId: string | null = null;
  private pendingUnlockAll = false;
  private unlockedAccountIds = new Set<string>();
  private decryptedAccountsById = new Map<string, Account>();
  private decryptedNamesById = new Map<string, string>();
  private isPrefetchingNames = false;
  private searchQueryBeforePasswordModal: string | null = null;

  constructor(
    private firestoreService: FirestoreService,
    private firebaseStorageService: FirebaseStorageService,
    private authService: AuthService,
    private ngZone: NgZone,
    private cdr: ChangeDetectorRef
  ) {
    // Expose the observables directly
    this.accounts$ = this.firestoreService.approvedUsers$;
    this.isLoading$ = this.firestoreService.isLoading$;
  }

  async verifyAdminPassword() {
    if (this.isVerifyingPassword) {
      return;
    }

    if (!this.pendingUnlockAll && !this.pendingUnlockAccountId) {
      this.passwordError = 'Select an account to unlock.';
      this.focusPasswordField();
      return;
    }

    this.passwordError = '';
    const password = (this.adminPasswordInput || '').trim();

    if (!password) {
      this.passwordError = 'Please enter your password.';
      this.focusPasswordField();
      return;
    }

    this.isVerifyingPassword = true;

    try {
      const ok = await this.authService.verifyCurrentAdminPassword(password);
      if (!ok) {
        this.passwordError = 'Incorrect password.';
        this.focusPasswordField();
        return;
      }

      if (this.pendingUnlockAll) {
        await this.unlockAllAccounts();
      } else if (this.pendingUnlockAccountId) {
        await this.unlockAccountById(this.pendingUnlockAccountId);
      }
      this.ngZone.run(() => {
        this.resetPasswordModalState();
        this.cdr.markForCheck();
      });
    } catch (error) {
      console.error('Error verifying admin password:', error);
      this.passwordError = 'Unable to verify password. Please try again.';
    } finally {
      this.isVerifyingPassword = false;
      this.cdr.markForCheck();
    }
  }

  ngOnInit() {
    
    // Start locked; reveal only after password verification.
    this.showPasswordModal = false;
    
    // Subscribe only to handle selection logic
    this.subscription = this.accounts$.subscribe(
      (users) => {
        
        const mappedUsers = (users as any[]).map((user) => this.mapAccount(user));
        this.encryptedAccounts = mappedUsers;
        this.pruneUnlockedAccounts(mappedUsers);
        this.rebuildVisibleAccounts();
        void this.prefetchDecryptedNamesIfNeeded();
      },
      (error) => {
        console.error('=== ERROR IN APPROVED USERS SUBSCRIPTION ===', error);
      }
    );

  }

  filterAccounts() {
    const statusFilteredAccounts = this.accounts.filter((acc) =>
      this.matchesStatusFilter(acc),
    );

    if (!this.searchQuery.trim()) {
      this.filteredAccounts = statusFilteredAccounts;
    } else {
      const query = this.searchQuery.toLowerCase();
      this.filteredAccounts = statusFilteredAccounts.filter(acc =>
        (acc.fullName?.toLowerCase().includes(query) || false) ||
        (acc.email?.toLowerCase().includes(query) || false) ||
        (acc.contactNumber?.toLowerCase().includes(query) || false) ||
        (acc.address?.toLowerCase().includes(query) || false)
      );
    }

    this.ensureCurrentPageInBounds();
  }

  private async unlockAccountById(accountId: string): Promise<void> {
    const admin = this.authService.currentAdmin();
    if (!admin?.id) {
      throw new Error('No authenticated admin found.');
    }
    try {
      const decryptedUser = await this.firestoreService.getDecryptedUser(accountId, 'approved_users', admin.id);
      const mappedAccount = this.mapAccount({ ...(decryptedUser ?? {}), id: accountId });
      this.ngZone.run(() => {
        this.decryptedAccountsById.set(accountId, mappedAccount);
        this.unlockedAccountIds.add(accountId);
        this.rebuildVisibleAccounts();
        this.cdr.detectChanges();
      });
    } catch (error) {
      console.error('Failed to load decrypted account:', error);
      throw error;
    }
  }

  private pruneUnlockedAccounts(latestAccounts: Account[]): void {
    const ids = new Set(latestAccounts.map((account) => account.id));
    for (const unlockedId of Array.from(this.unlockedAccountIds)) {
      if (!ids.has(unlockedId)) {
        this.unlockedAccountIds.delete(unlockedId);
        this.decryptedAccountsById.delete(unlockedId);
      }
    }
  }

  private rebuildVisibleAccounts(): void {
    this.accounts = this.encryptedAccounts.map((baseAccount) => {
      const decryptedName = this.decryptedNamesById.get(baseAccount.id);
      const baseWithName = decryptedName
        ? { ...baseAccount, fullName: decryptedName }
        : baseAccount;

      const decryptedAccount = this.decryptedAccountsById.get(baseAccount.id);
      if (!decryptedAccount) {
        return baseWithName;
      }
      return {
        ...baseWithName,
        ...decryptedAccount,
        fullName: decryptedAccount.fullName || baseWithName.fullName,
        id: baseAccount.id,
      };
    });
    this.filterAccounts();
  }

  private async prefetchDecryptedNamesIfNeeded(): Promise<void> {
    if (this.isPrefetchingNames) {
      return;
    }

    const needsNames = this.encryptedAccounts.some(
      (account) => !account.fullName && !this.decryptedNamesById.has(account.id)
    );

    if (!needsNames) {
      return;
    }

    const admin = this.authService.currentAdmin();
    if (!admin?.id) {
      return;
    }

    this.isPrefetchingNames = true;
    try {
      const decryptedUsers = await this.firestoreService.getDecryptedApprovedUsers(admin.id);
      const nextNames = new Map<string, string>(this.decryptedNamesById);

      for (const raw of decryptedUsers as any[]) {
        const id = typeof raw?.id === 'string' ? raw.id : '';
        const fullName = typeof raw?.fullName === 'string' ? raw.fullName.trim() : '';
        if (!id || !fullName) {
          continue;
        }
        nextNames.set(id, fullName);
      }

      this.ngZone.run(() => {
        this.decryptedNamesById = nextNames;
        this.rebuildVisibleAccounts();
        this.cdr.markForCheck();
      });
    } catch (error) {
      console.error('Failed to prefetch decrypted full names:', error);
    } finally {
      this.isPrefetchingNames = false;
    }
  }

  private mapAccount(raw: any): Account {
    const account: Account = {
      id: typeof raw?.id === 'string' ? raw.id : '',
      fullName: typeof raw?.fullName === 'string' ? raw.fullName : undefined,
      email: typeof raw?.email === 'string' ? raw.email : '',
      address: typeof raw?.address === 'string' ? raw.address : '',
      dateOfBirth: typeof raw?.dateOfBirth === 'string' ? raw.dateOfBirth : '',
      contactNumber: typeof raw?.contactNumber === 'string' ? raw.contactNumber : '',
      idPhotoPath: typeof raw?.idPhotoPath === 'string'
        ? raw.idPhotoPath
        : (typeof raw?.idPhotoFront === 'string' ? raw.idPhotoFront : ''),
      idPhotoFront: typeof raw?.idPhotoFront === 'string' ? raw.idPhotoFront : undefined,
      idPhotoSelfie: typeof raw?.idPhotoSelfie === 'string' ? raw.idPhotoSelfie : undefined,
      profilePhotoUrl: typeof raw?.profilePhotoUrl === 'string' ? raw.profilePhotoUrl : undefined,
      profilePictureUrl: typeof raw?.profilePictureUrl === 'string' ? raw.profilePictureUrl : undefined,
      profileImageUrl: typeof raw?.profileImageUrl === 'string' ? raw.profileImageUrl : undefined,
      photoUrl: typeof raw?.photoUrl === 'string' ? raw.photoUrl : undefined,
      avatarUrl: typeof raw?.avatarUrl === 'string' ? raw.avatarUrl : undefined,
      accountStatus: typeof raw?.accountStatus === 'string' ? raw.accountStatus : 'N/A',
      approvedAt: raw?.approvedAt ?? null,
      approvedBy: typeof raw?.approvedBy === 'string' ? raw.approvedBy : undefined,
      bannedAt: raw?.bannedAt ?? null,
      bannedUntil: raw?.bannedUntil ?? null,
      banType: typeof raw?.banType === 'string' ? raw.banType : undefined,
      isPermanent: raw?.isPermanent == true,
      banReasons: Array.isArray(raw?.banReasons)
        ? (raw.banReasons as unknown[])
            .map((reason) => (typeof reason === 'string' ? reason.trim() : ''))
            .filter((reason) => reason.length > 0)
        : [],
    };

    const encryptedFields = ['email', 'address', 'dateOfBirth', 'contactNumber'];
    for (const field of encryptedFields) {
      const cipherKey = `${field}_cipher`;
      if (typeof raw?.[cipherKey] === 'string') {
        (account as any)[cipherKey] = raw[cipherKey];
      }
    }

    return account;
  }

  onSearchChange() {
    this.currentPage = 1;
    this.filterAccounts();
  }

  onStatusFilterChange() {
    this.currentPage = 1;
    this.filterAccounts();
  }

  get paginatedAccounts(): Account[] {
    const start = (this.currentPage - 1) * this.cardsPerPage;
    return this.filteredAccounts.slice(start, start + this.cardsPerPage);
  }

  get totalPages(): number {
    return Math.max(1, Math.ceil(this.filteredAccounts.length / this.cardsPerPage));
  }

  get canGoPrevious(): boolean {
    return this.currentPage > 1;
  }

  get canGoNext(): boolean {
    return this.currentPage < this.totalPages;
  }

  get startItem(): number {
    if (this.filteredAccounts.length === 0) {
      return 0;
    }
    return (this.currentPage - 1) * this.cardsPerPage + 1;
  }

  get endItem(): number {
    return Math.min(this.currentPage * this.cardsPerPage, this.filteredAccounts.length);
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

  ngOnDestroy() {
      if (this.subscription) {
        this.subscription.unsubscribe();
      }
  }

  getApprovedDate(account: Account): Date | null {
    const value: any = (account as any).approvedAt;
    if (!value) {
      return null;
    }

    // Firestore Timestamp from web SDK
    if (typeof value.toDate === 'function') {
      return value.toDate();
    }

    if (value instanceof Date) {
      return value;
    }

    // Callable functions / JSON-serialized Timestamp from Admin SDK
    const seconds = value.seconds ?? value._seconds;
    const nanoseconds = value.nanoseconds ?? value._nanoseconds;
    if (typeof seconds === 'number') {
      const msFromNanos = typeof nanoseconds === 'number' ? nanoseconds / 1_000_000 : 0;
      return new Date(seconds * 1000 + msFromNanos);
    }

    // ISO string / epoch
    if (typeof value === 'string' || typeof value === 'number') {
      const date = new Date(value);
      return Number.isNaN(date.getTime()) ? null : date;
    }

    return null;
  }

  ban(account: Account) {
    this.accountToBan = account;
    this.resetBanReasons();
    this.showBanReasonsModal = true;
  }

  openUnbanConfirmation(account: Account) {
    this.accountToUnban = account;
    this.showUnbanConfirmationModal = true;
  }

  cancelUnban() {
    this.showUnbanConfirmationModal = false;
    this.accountToUnban = null;
  }

  async confirmUnban() {
    if (!this.accountToUnban || this.isProcessingUnban) {
      return;
    }
    
    const accountId = this.accountToUnban.id;
    this.isProcessingUnban = true;
    
    try {
      await this.firestoreService.updateDocument('approved_users', accountId, {
        accountStatus: 'approved',
        bannedUntil: null,
        banReasons: [],
        bannedAt: null,
        banType: null,
        isPermanent: false,
      });
      
      this.ngZone.run(() => {
        this.showUnbanConfirmationModal = false;
        this.accountToUnban = null;
        this.isProcessingUnban = false;
        this.cdr.markForCheck();
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

    if (this.isProcessingBan) {
      return;
    }

    if (!this.accountToBan) {
      return;
    }

    this.isProcessingBan = true;

    const accountId = this.accountToBan.id;

    try {
      let banUntil: Date | null = null;
      const isPermanent = this.banDuration === 'permanent';
      if (!isPermanent) {
        banUntil = new Date();
        banUntil.setDate(banUntil.getDate() + 7);
      }

      const updateData: any = {
        accountStatus: 'BANNED',
        banReasons: this.selectedBanReasons,
        bannedAt: new Date(),
        bannedUntil: banUntil,
        banType: isPermanent ? 'permanent' : 'temporary',
        isPermanent,
      };

      await this.firestoreService.updateDocument(
        'approved_users',
        accountId,
        updateData,
      );

      this.ngZone.run(() => {
        this.showBanConfirmationModal = false;
        this.accountToBan = null;
        this.banDuration = null;
        this.selectedBanReasons = [];
        this.resetBanReasons();
        this.isProcessingBan = false;
        this.cdr.markForCheck();
      });
    } catch (error) {
      console.error('Error banning account:', error);
      alert('Failed to ban account. Please try again.');
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
    this.idModalTitle = 'VALID ID';
    this.idModalUrl = url;
    this.showIdModal = true;
  }

  private async unlockAllAccounts(): Promise<void> {
    const admin = this.authService.currentAdmin();
    if (!admin?.id) {
      throw new Error('No authenticated admin found.');
    }

    const decryptedUsers = await this.firestoreService.getDecryptedApprovedUsers(
      admin.id
    );

    this.ngZone.run(() => {
      for (const raw of decryptedUsers as any[]) {
        const id = typeof raw?.id === 'string' ? raw.id : '';
        if (!id) {
          continue;
        }
        const mappedAccount = this.mapAccount({ ...(raw ?? {}), id });
        this.decryptedAccountsById.set(id, mappedAccount);
        this.unlockedAccountIds.add(id);
      }
      this.rebuildVisibleAccounts();
      this.cdr.detectChanges();
    });
  }

  openSelfieWithIdModal(account: Account) {
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

  trackById(_: number, acc: Account) {
    return acc.id;
  }

  getIdPhotoUrl(account: Account): string | null {
    const path = (account.idPhotoPath || account.idPhotoFront || '').trim();
    if (!path) {
      return null;
    }
    if (path.startsWith('http')) {
      return path;
    }
    return this.firebaseStorageService.getDownloadUrl(path);
  }

  getSelfieWithIdUrl(account: Account): string | null {
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

  closePasswordModal() {
    if (this.isVerifyingPassword) return;
    this.resetPasswordModalState();
  }

  openDecryptModal(accountId: string) {
    if (!accountId || this.isVerifyingPassword || this.isAccountUnlocked(accountId)) {
      return;
    }
    this.searchQueryBeforePasswordModal = this.searchQuery;
    this.pendingUnlockAll = false;
    this.pendingUnlockAccountId = accountId;
    this.adminPasswordInput = '';
    this.passwordError = '';
    this.showPasswordModal = true;
    this.focusPasswordField();
  }

  openUnlockAllModal() {
    if (this.isVerifyingPassword || !this.hasLockedAccounts) {
      return;
    }
    this.searchQueryBeforePasswordModal = this.searchQuery;
    this.pendingUnlockAll = true;
    this.pendingUnlockAccountId = null;
    this.adminPasswordInput = '';
    this.passwordError = '';
    this.showPasswordModal = true;
    this.focusPasswordField();
  }

  getProfilePhotoUrl(account: Account): string | null {
    const candidates = [
      account.profilePhotoUrl,
      account.profilePictureUrl,
      account.profileImageUrl,
      account.photoUrl,
      account.avatarUrl,
    ];

    for (const finalUrl of candidates) {
      const value = (finalUrl || '').trim();
      if (!value) {
        continue;
      }
      if (value.startsWith('http://') || value.startsWith('https://')) {
        return value;
      }
      return this.firebaseStorageService.getDownloadUrl(value);
    }

    return null;
  }

  getAccountInitial(account: Account): string {
    const name = this.getPublicName(account, { fallback: 'U' });
    if (!name) {
      return 'U';
    }
    return name[0].toUpperCase();
  }

  getPublicName(
    account: Account | null | undefined,
    options?: { fallback?: string }
  ): string {
    const fallback = options?.fallback ?? '[ENCRYPTED]';
    if (!account) {
      return fallback;
    }

    const visibleName = (account.fullName || '').trim();

    return visibleName || fallback;
  }

  getEncryptedValue(account: Account, field: string): string {
    const cipherKey = `${field}_cipher`;
    const cipherValue = (account as any)[cipherKey];
    if (typeof cipherValue === 'string' && cipherValue.trim()) {
      return cipherValue;
    }
    return '[ENCRYPTED]';
  }

  getDisplayValue(account: Account, field: string): string {
    if (field === 'fullName') {
      return this.getPublicName(account, { fallback: 'User' });
    }
    if (this.isAccountUnlocked(account.id)) {
      const plainValue = (account as any)[field];
      if (plainValue == null || plainValue === '') {
        return 'N/A';
      }
      return String(plainValue);
    }
    return this.getEncryptedValue(account, field);
  }
  private resetPasswordModalState(): void {
    this.showPasswordModal = false;
    this.pendingUnlockAccountId = null;
    this.pendingUnlockAll = false;
    this.adminPasswordInput = '';
    this.passwordError = '';
    if (
      this.searchQueryBeforePasswordModal !== null &&
      this.searchQuery !== this.searchQueryBeforePasswordModal
    ) {
      this.searchQuery = this.searchQueryBeforePasswordModal;
      this.filterAccounts();
    }
    this.searchQueryBeforePasswordModal = null;
  }

  private focusPasswordField(): void {
    setTimeout(() => {
      this.adminPasswordField?.nativeElement?.focus();
      this.adminPasswordField?.nativeElement?.select();
    });
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

  isAccountUnlocked(accountId: string): boolean {
    return this.unlockedAccountIds.has(accountId);
  }

  get hasLockedAccounts(): boolean {
    return this.filteredAccounts.some((account) => !this.isAccountUnlocked(account.id));
  }

  private normalizeAccountStatus(value: unknown): string {
    return (value ?? '').toString().trim().toUpperCase();
  }

  private matchesStatusFilter(account: Account): boolean {
    switch (this.accountStatusFilter) {
      case 'active':
        return !this.isBanned(account);
      case 'all':
        return true;
      case 'banned':
        return this.isBanned(account);
      case 'temporary':
        return this.isTemporaryBan(account);
      case 'permanent':
        return this.isPermanentBan(account);
      default:
        return !this.isBanned(account);
    }
  }

  private isBanned(account: Account): boolean {
    return this.normalizeAccountStatus(account.accountStatus) === 'BANNED';
  }

  // Check if account has a temporary ban
  isTemporaryBan(account: Account): boolean {
    return this.isBanned(account) && !this.isPermanentBan(account) && account.bannedUntil != null;
  }

  isPermanentBan(account: Account): boolean {
    if (!this.isBanned(account)) {
      return false;
    }
    if (account.isPermanent == true) {
      return true;
    }
    const normalizedBanType = (account.banType ?? '').trim().toLowerCase();
    if (normalizedBanType == 'permanent') {
      return true;
    }
    return account.bannedUntil == null;
  }
}


import { Injectable, NgZone } from '@angular/core';
import { 
  collection, 
  query, 
  where, 
  getDocs, 
  limit,
  orderBy,
  startAfter,
  addDoc, 
  updateDoc, 
  deleteDoc, 
  doc,
  setDoc,
  Timestamp,
  onSnapshot,
  QueryDocumentSnapshot,
  DocumentData,
  Unsubscribe
} from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { db, functions } from '../config/firebase.config';
import { BehaviorSubject, Observable } from 'rxjs';

@Injectable({
  providedIn: 'root'
})
export class FirestoreService {
  // Use BehaviorSubject with initial empty array - always has a value
  private pendingUsersSubject = new BehaviorSubject<any[]>([]);
  private approvedUsersSubject = new BehaviorSubject<any[]>([]);
  private pendingReportsSubject = new BehaviorSubject<any[]>([]);
  private approvedReportsSubject = new BehaviorSubject<any[]>([]);
  private reportsSubject = new BehaviorSubject<any[]>([]);
  private flaggedReportsSubject = new BehaviorSubject<any[]>([]);
  private hasMoreReportsSubject = new BehaviorSubject<boolean>(true);
  
  // Track loading state
  private isLoadingSubject = new BehaviorSubject<boolean>(true);
  
  public pendingUsers$: Observable<any[]> = this.pendingUsersSubject.asObservable();
  public approvedUsers$: Observable<any[]> = this.approvedUsersSubject.asObservable();
  public pendingReports$: Observable<any[]> = this.pendingReportsSubject.asObservable();
  public approvedReports$: Observable<any[]> = this.approvedReportsSubject.asObservable();
  public reports$: Observable<any[]> = this.reportsSubject.asObservable();
  public flaggedReports$: Observable<any[]> = this.flaggedReportsSubject.asObservable();
  public hasMoreReports$: Observable<boolean> = this.hasMoreReportsSubject.asObservable();
  public isLoading$: Observable<boolean> = this.isLoadingSubject.asObservable();
  
  private pendingUsersUnsubscribe?: Unsubscribe;
  private approvedUsersUnsubscribe?: Unsubscribe;
  private reportsUnsubscribe?: Unsubscribe;
  private readonly reportsPageSize = 120;
  private reportsRealtime: any[] = [];
  private reportsPaged: any[] = [];
  private reportsRealtimeCursor: QueryDocumentSnapshot<DocumentData> | null = null;
  private reportsPageCursor: QueryDocumentSnapshot<DocumentData> | null = null;
  private isLoadingReportsPage = false;

  constructor(private ngZone: NgZone) {
    console.log('=== FIRESTORE SERVICE CONSTRUCTOR ===');
    console.log('Timestamp:', new Date().toISOString());
    
    // Load initial data and set up listeners
    this.initializeData();
  }

  private async initializeData() {
    console.log('=== INITIALIZING DATA AND LISTENERS ===');
    
    try {
      // Load initial data FIRST - wait for it to complete
      await this.loadInitialData();
      console.log('Initial data loaded, now setting up listeners...');
      
      // Then set up real-time listeners AFTER data is loaded
      this.initializeRealtimeListeners();
    } catch (error) {
      console.error('Error during initialization:', error);
      // Still try to set up listeners even if initial load fails
      this.initializeRealtimeListeners();
    }
  }

  private async loadInitialData() {
    try {
      console.log('=== LOADING INITIAL DATA ===');
      console.log('Time:', new Date().toISOString());
      
      // Load pending users
      const pendingRef = collection(db, 'pending_users');
      const pendingSnapshot = await getDocs(pendingRef);
      const pendingUsers = pendingSnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));
      console.log('Initial pending users loaded:', pendingUsers.length);
      this.ngZone.run(() => {
        this.pendingUsersSubject.next(pendingUsers);
      });
      
      // Load approved users
      const approvedRef = collection(db, 'approved_users');
      const approvedSnapshot = await getDocs(approvedRef);
      const approvedUsers = approvedSnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));
      console.log('Initial approved users loaded:', approvedUsers.length);
      this.ngZone.run(() => {
        this.approvedUsersSubject.next(approvedUsers);
      });

      // Seed report streams with a bounded first page.
      const reportsSeedQuery = query(
        collection(db, 'reports'),
        orderBy('reportedAt', 'desc'),
        limit(this.reportsPageSize),
      );
      const reportsSnapshot = await getDocs(reportsSeedQuery);
      const reports = reportsSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      if (reportsSnapshot.docs.length > 0) {
        this.reportsRealtimeCursor = reportsSnapshot.docs[reportsSnapshot.docs.length - 1];
        this.reportsPageCursor = this.reportsRealtimeCursor;
      }
      this.reportsRealtime = reports;
      this.ngZone.run(() => {
        this.hasMoreReportsSubject.next(reportsSnapshot.docs.length === this.reportsPageSize);
        this.emitReportStreams(this.getMergedReports());
      });
      
      console.log('=== INITIAL DATA LOADED AND EMITTED ===');
      console.log('Pending:', pendingUsers.length, 'Approved:', approvedUsers.length);
      
      // Mark loading as complete AFTER data has been loaded
      console.log('Setting isLoading to false');
      this.ngZone.run(() => {
        this.isLoadingSubject.next(false);
      });
    } catch (error) {
      console.error('Error loading initial data:', error);
      // Mark loading as complete even on error
      this.ngZone.run(() => {
        this.isLoadingSubject.next(false);
      });
      throw error;
    }
  }

  private initializeRealtimeListeners() {
    console.log('=== INITIALIZING REAL-TIME LISTENERS IN SERVICE ===');
    console.log('Database instance:', db);
    console.log('Setting up listeners NOW');
    
    try {
      // Pending users listener
      const pendingRef = collection(db, 'pending_users');
      console.log('Pending users collection path:', pendingRef.path);
      
      this.pendingUsersUnsubscribe = onSnapshot(
        pendingRef, 
        {
          // Include metadata to get immediate callback even with cached data
          includeMetadataChanges: false
        },
        (snapshot) => {
          this.ngZone.run(() => {
            const users = snapshot.docs.map(doc => {
              const data = { id: doc.id, ...doc.data() };
              return data;
            });
            console.log('=== PENDING USERS SNAPSHOT RECEIVED ===');
            console.log('Time:', new Date().toISOString());
            console.log('Count:', users.length);
            console.log('From cache:', snapshot.metadata.fromCache);
            console.log('Has pending writes:', snapshot.metadata.hasPendingWrites);
            
            // Always emit, even if empty
            this.pendingUsersSubject.next(users);
            console.log('Emitted to pendingUsersSubject');
          });
        },
        (error) => {
          console.error('=== PENDING USERS LISTENER ERROR ===', error);
          this.ngZone.run(() => {
            // Emit empty array on error so subscribers still get notified
            this.pendingUsersSubject.next([]);
          });
        }
      );
      
      // Approved users listener
      const approvedRef = collection(db, 'approved_users');
      console.log('Approved users collection path:', approvedRef.path);
      
      this.approvedUsersUnsubscribe = onSnapshot(
        approvedRef,
        {
          includeMetadataChanges: false
        },
        (snapshot) => {
          this.ngZone.run(() => {
            const users = snapshot.docs.map(doc => {
              const data = { id: doc.id, ...doc.data() };
              return data;
            });
            console.log('=== APPROVED USERS SNAPSHOT RECEIVED ===');
            console.log('Time:', new Date().toISOString());
            console.log('Count:', users.length);
            console.log('From cache:', snapshot.metadata.fromCache);
            console.log('Has pending writes:', snapshot.metadata.hasPendingWrites);
            
            // Always emit, even if empty
            this.approvedUsersSubject.next(users);
            console.log('Emitted to approvedUsersSubject');
          });
        },
        (error) => {
          console.error('=== APPROVED USERS LISTENER ERROR ===', error);
          this.ngZone.run(() => {
            // Emit empty array on error so subscribers still get notified
            this.approvedUsersSubject.next([]);
          });
        }
      );

      // Reports listener (bounded, newest-first page only)
      const reportsQuery = query(
        collection(db, 'reports'),
        orderBy('reportedAt', 'desc'),
        limit(this.reportsPageSize),
      );
      this.reportsUnsubscribe = onSnapshot(
        reportsQuery,
        (snapshot) => {
          this.ngZone.run(() => {
            this.reportsRealtime = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })) as any[];
            if (snapshot.docs.length > 0) {
              this.reportsRealtimeCursor = snapshot.docs[snapshot.docs.length - 1];
              if (this.reportsPaged.length === 0) {
                this.reportsPageCursor = this.reportsRealtimeCursor;
              }
            } else {
              this.reportsRealtimeCursor = null;
              if (this.reportsPaged.length === 0) {
                this.reportsPageCursor = null;
              }
            }
            this.hasMoreReportsSubject.next(snapshot.docs.length === this.reportsPageSize);
            this.emitReportStreams(this.getMergedReports());
          });
        },
        (error) => {
          console.error('=== REPORTS LISTENER ERROR ===', error);
          this.ngZone.run(() => {
            this.reportsRealtime = [];
            this.reportsPaged = [];
            this.reportsRealtimeCursor = null;
            this.reportsPageCursor = null;
            this.hasMoreReportsSubject.next(false);
            this.emitReportStreams([]);
          });
        }
      );
      
      console.log('=== LISTENERS SETUP COMPLETE ===');
      console.log('Both listeners are now active and waiting for snapshots');
    } catch (error) {
      console.error('=== CRITICAL ERROR SETTING UP LISTENERS ===', error);
    }
  }

  private getMergedReports(): any[] {
    return this.mergeUniqueById(this.reportsRealtime, this.reportsPaged);
  }

  private mergeUniqueById(primary: any[], secondary: any[]): any[] {
    const merged: any[] = [];
    const seen = new Set<string>();

    for (const report of primary) {
      const id = (report?.id ?? '').toString();
      if (!id || seen.has(id)) continue;
      seen.add(id);
      merged.push(report);
    }

    for (const report of secondary) {
      const id = (report?.id ?? '').toString();
      if (!id || seen.has(id)) continue;
      seen.add(id);
      merged.push(report);
    }

    return merged;
  }

  private emitReportStreams(reports: any[]): void {
    this.reportsSubject.next(reports);
    this.pendingReportsSubject.next(this.filterPendingReports(reports));
    this.approvedReportsSubject.next(this.filterApprovedReports(reports));
    this.flaggedReportsSubject.next(this.filterFlaggedReports(reports));
  }

  private filterPendingReports(reports: any[]): any[] {
    const now = Date.now();
    const thirtyDaysAgoTime = now - (30 * 24 * 60 * 60 * 1000);

    return reports.filter((report) => {
      const status = (report?.status ?? '').toString().toUpperCase();
      if (status === 'PENDING' || status === 'RESPONDING' || status === 'ON SCENE') {
        return true;
      }
      if (status === 'RESOLVED') {
        return this.isWithinWindow(report?.resolvedAt, thirtyDaysAgoTime);
      }
      if (status === 'FLAGGED') {
        return this.isWithinWindow(report?.flaggedAt, thirtyDaysAgoTime);
      }
      return false;
    });
  }

  private filterApprovedReports(reports: any[]): any[] {
    return reports.filter((report) => (report?.status ?? '').toString().toUpperCase() === 'APPROVED');
  }

  private filterFlaggedReports(reports: any[]): any[] {
    const now = Date.now();
    const thirtyDaysAgoTime = now - (30 * 24 * 60 * 60 * 1000);

    return reports.filter((report) => {
      const status = (report?.status ?? '').toString().toUpperCase();
      if (status !== 'ADMIN_FLAGGED') return false;
      return this.isWithinWindow(report?.flaggedAt, thirtyDaysAgoTime);
    });
  }

  private coerceTimestampMs(value: any): number | null {
    if (!value) return null;
    if (typeof value?.toDate === 'function') {
      const date = value.toDate();
      const ms = date instanceof Date ? date.getTime() : NaN;
      return Number.isFinite(ms) ? ms : null;
    }
    const parsed = new Date(value);
    const ms = parsed.getTime();
    return Number.isFinite(ms) ? ms : null;
  }

  private isWithinWindow(value: any, thresholdMs: number): boolean {
    const timestampMs = this.coerceTimestampMs(value);
    if (timestampMs === null) {
      // Keep legacy records without tracked event timestamps.
      return true;
    }
    return timestampMs >= thresholdMs;
  }

  async loadMoreReportsPage(): Promise<void> {
    if (this.isLoadingReportsPage || !this.hasMoreReportsSubject.value) {
      return;
    }
    if (!this.reportsPageCursor) {
      this.reportsPageCursor = this.reportsRealtimeCursor;
    }
    if (!this.reportsPageCursor) {
      this.hasMoreReportsSubject.next(false);
      return;
    }

    this.isLoadingReportsPage = true;
    try {
      const nextPageQuery = query(
        collection(db, 'reports'),
        orderBy('reportedAt', 'desc'),
        startAfter(this.reportsPageCursor),
        limit(this.reportsPageSize),
      );
      const nextPageSnapshot = await getDocs(nextPageQuery);
      const nextReports = nextPageSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })) as any[];

      if (nextPageSnapshot.docs.length > 0) {
        this.reportsPageCursor = nextPageSnapshot.docs[nextPageSnapshot.docs.length - 1];
      } else {
        this.reportsPageCursor = null;
      }

      this.ngZone.run(() => {
        this.reportsPaged = this.mergeUniqueById(this.reportsPaged, nextReports);
        this.hasMoreReportsSubject.next(nextPageSnapshot.docs.length === this.reportsPageSize);
        this.emitReportStreams(this.getMergedReports());
      });
    } catch (error) {
      console.error('Failed to load more reports page:', error);
      throw error;
    } finally {
      this.isLoadingReportsPage = false;
    }
  }

  // Get all documents from a collection
  async getCollection(collectionName: string): Promise<any[]> {
    console.log(`Fetching collection: ${collectionName}`);
    try {
      const collectionRef = collection(db, collectionName);
      console.log('Collection reference created:', collectionRef.path);
      
      const querySnapshot = await getDocs(collectionRef);
      console.log(`Query executed. Documents found: ${querySnapshot.size}`);
      
      const results = querySnapshot.docs.map(doc => {
        const data = { id: doc.id, ...doc.data() };
        console.log('Document:', doc.id, data);
        return data;
      });
      
      console.log(`Returning ${results.length} documents from ${collectionName}`);
      return results;
    } catch (error: any) {
      console.error(`Error fetching collection ${collectionName}:`, error);
      console.error('Error code:', error.code);
      console.error('Error message:', error.message);
      throw error;
    }
  }

  // Get documents with a filter
  async queryCollection(collectionName: string, field: string, operator: any, value: any): Promise<any[]> {
    const q = query(collection(db, collectionName), where(field, operator, value));
    const querySnapshot = await getDocs(q);
    return querySnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
  }

  // Listen to documents with a filter (real-time)
  listenToCollectionWhere(
    collectionName: string,
    field: string,
    operator: any,
    value: any,
    callback: (docs: any[]) => void,
    onError?: (error: any) => void,
  ): Unsubscribe {
    const q = query(collection(db, collectionName), where(field, operator, value));
    return onSnapshot(
      q,
      (snapshot) => {
        const docs = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
        this.ngZone.run(() => callback(docs));
      },
      (error) => {
        console.error(`Snapshot error for ${collectionName} where ${field} ${operator} ${value}:`, error);
        if (onError) {
          this.ngZone.run(() => onError(error));
        }
      }
    );
  }

  // Clean up listeners (call on app destroy if needed)
  disposeReportListeners() {
    if (this.reportsUnsubscribe) {
      this.reportsUnsubscribe();
      this.reportsUnsubscribe = undefined;
    }
    this.reportsRealtime = [];
    this.reportsPaged = [];
    this.reportsRealtimeCursor = null;
    this.reportsPageCursor = null;
    this.hasMoreReportsSubject.next(false);
    this.emitReportStreams([]);
  }

  // Add a document to a collection
  async addDocument(collectionName: string, data: any): Promise<string> {
    const docRef = await addDoc(collection(db, collectionName), {
      ...data,
      createdAt: Timestamp.now()
    });
    return docRef.id;
  }

  // Update a document
  async updateDocument(collectionName: string, docId: string, data: any): Promise<void> {
    const docRef = doc(db, collectionName, docId);
    await updateDoc(docRef, {
      ...data,
      updatedAt: Timestamp.now()
    });
  }

  // Delete a document
  async deleteDocument(collectionName: string, docId: string): Promise<void> {
    await deleteDoc(doc(db, collectionName, docId));
  }

  // Collections specific to your app
  async getUsers() {
    return this.getCollection('users');
  }

  async getSemiAdmins() {
    return this.getCollection('semi_admins');
  }

  async getUserByUsername(username: string) {
    const results = await this.queryCollection('users', 'username', '==', username);
    return results.length > 0 ? results[0] : null;
  }

  async getSemiAdminByUsername(username: string) {
    const results = await this.queryCollection('semi_admins', 'username', '==', username);
    return results.length > 0 ? results[0] : null;
  }

  // Account approval methods
  async getPendingUsers() {
    return this.getCollection('pending_users');
  }

  async approvePendingUser(user: any, adminUsername: string) {
    try {
      const { id, ...data } = user;
      const createdAt = data['createdAt'] || Timestamp.now();

      console.log('Starting approval process for user:', id);
      console.log('User data to be approved:', data);

      // STEP 1: Move pending user into approved_users collection FIRST
      await setDoc(doc(db, 'approved_users', id), {
        ...data,
        createdAt,
        accountStatus: 'approved',
        approvedAt: Timestamp.now(),
        approvedBy: adminUsername,
        updatedAt: Timestamp.now()
      });

      console.log('SUCCESS: User saved to approved_users collection');

      // STEP 2: Only delete from pending after successful save
      await deleteDoc(doc(db, 'pending_users', id));
      
      console.log('SUCCESS: User removed from pending_users collection');
      console.log('Approval process completed successfully');
    } catch (error: any) {
      console.error('FAILED: Error in approvePendingUser:', error);
      console.error('Error code:', error.code);
      console.error('Error message:', error.message);
      throw new Error(`Failed to approve user: ${error.message || 'Unknown error'}`);
    }
  }

  async rejectPendingUser(user: any, adminUsername: string, reason?: string) {
    try {
      const { id } = user;
      
      console.log('Starting rejection process for user:', id);
      console.log('Rejection reason:', reason);

      // Simply delete from pending_users collection
      // No need to move to another collection
      await deleteDoc(doc(db, 'pending_users', id));
      
      console.log('SUCCESS: User removed from pending_users collection');
      console.log('Rejection process completed successfully');
    } catch (error: any) {
      console.error('FAILED: Error in rejectPendingUser:', error);
      console.error('Error code:', error.code);
      console.error('Error message:', error.message);
      throw new Error(`Failed to reject user: ${error.message || 'Unknown error'}`);
    }
  }

  async getApprovedUsers() {
    return this.getCollection('approved_users');
  }

  async getRejectedUsers() {
    return this.queryCollection('users', 'accountStatus', '==', 'rejected');
  }

  /**
   * Get decrypted pending users via Cloud Function
   * @param adminId - The ID of the authenticated admin
   */
  async getDecryptedPendingUsers(adminId: string): Promise<any[]> {
    try {
      const getDecryptedUsersCallable = httpsCallable(functions, 'getDecryptedUsers');
      const result = await getDecryptedUsersCallable({
        collection: 'pending_users',
        adminId
      });
      
      const data = result.data as { success: boolean; users: any[] };
      if (data.success) {
        return data.users;
      }
      throw new Error('Failed to decrypt users');
    } catch (error) {
      console.error('Error getting decrypted pending users:', error);
      // Fall back to raw data if decryption fails
      return this.getCollection('pending_users');
    }
  }

  /**
   * Get decrypted approved users via Cloud Function
   * @param adminId - The ID of the authenticated admin
   */
  async getDecryptedApprovedUsers(adminId: string): Promise<any[]> {
    try {
      const getDecryptedUsersCallable = httpsCallable(functions, 'getDecryptedUsers');
      const result = await getDecryptedUsersCallable({
        collection: 'approved_users',
        adminId
      });
      
      const data = result.data as { success: boolean; users: any[] };
      if (data.success) {
        return data.users;
      }
      throw new Error('Failed to decrypt users');
    } catch (error) {
      console.error('Error getting decrypted approved users:', error);
      // Fall back to raw data if decryption fails
      return this.getCollection('approved_users');
    }
  }

  /**
   * Get single decrypted user via Cloud Function
   * @param userId - The user document ID
   * @param collectionName - The collection to fetch from
   * @param adminId - The ID of the authenticated admin
   */
  async getDecryptedUser(userId: string, collectionName: string, adminId: string): Promise<any> {
    try {
      const decryptUserDataCallable = httpsCallable(functions, 'decryptUserData');
      const result = await decryptUserDataCallable({
        userId,
        collection: collectionName,
        adminId
      });
      
      const data = result.data as { success: boolean; userData: any };
      if (data.success) {
        return data.userData;
      }
      throw new Error('Failed to decrypt user');
    } catch (error) {
      console.error('Error getting decrypted user:', error);
      throw error;
    }
  }

  /**
   * Migrate existing unencrypted data to encrypted format
   * @param adminId - The ID of the authenticated admin
   */
  async migrateToEncrypted(adminId: string): Promise<string> {
    try {
      const migrateCallable = httpsCallable(functions, 'migrateToEncrypted');
      const result = await migrateCallable({ adminId });
      
      const data = result.data as { success: boolean; message: string };
      if (data.success) {
        return data.message;
      }
      throw new Error('Migration failed');
    } catch (error) {
      console.error('Error migrating to encrypted:', error);
      throw error;
    }
  }
}

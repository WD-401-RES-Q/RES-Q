import { Injectable, NgZone } from '@angular/core';
import { 
  collection, 
  query, 
  where, 
  getDocs, 
  addDoc, 
  updateDoc, 
  deleteDoc, 
  doc,
  setDoc,
  Timestamp,
  CollectionReference,
  DocumentData,
  onSnapshot,
  Unsubscribe
} from 'firebase/firestore';
import { db } from './firebase.config';
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
  
  // Track loading state
  private isLoadingSubject = new BehaviorSubject<boolean>(true);
  
  public pendingUsers$: Observable<any[]> = this.pendingUsersSubject.asObservable();
  public approvedUsers$: Observable<any[]> = this.approvedUsersSubject.asObservable();
  public pendingReports$: Observable<any[]> = this.pendingReportsSubject.asObservable();
  public approvedReports$: Observable<any[]> = this.approvedReportsSubject.asObservable();
  public reports$: Observable<any[]> = this.reportsSubject.asObservable();
  public flaggedReports$: Observable<any[]> = this.flaggedReportsSubject.asObservable();
  public isLoading$: Observable<boolean> = this.isLoadingSubject.asObservable();
  
  private pendingUsersUnsubscribe?: Unsubscribe;
  private approvedUsersUnsubscribe?: Unsubscribe;
  private pendingReportsUnsubscribe?: Unsubscribe;
  private approvedReportsUnsubscribe?: Unsubscribe;
  private reportsUnsubscribe?: Unsubscribe;
  private flaggedReportsUnsubscribe?: Unsubscribe;

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

      // Load all reports once (seed streams before listeners fire)
      const reportsRef = collection(db, 'reports');
      const reportsSnapshot = await getDocs(reportsRef);
      const reports = reportsSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      this.ngZone.run(() => {
        this.reportsSubject.next(reports);
        // Seed filtered subjects too for immediate UI without waiting on snapshots
        const pendingSeed = reports.filter((r: any) => (r.status ?? '').toString().toLowerCase() === 'pending');
        const approvedSeed = reports.filter((r: any) => {
          const s = (r.status ?? '').toString().toLowerCase();
          return s === 'approved' || s === 'resolved';
        });
        const flaggedSeed = reports.filter((r: any) => (r.status ?? '').toString().toLowerCase() === 'flagged');
        this.pendingReportsSubject.next(pendingSeed);
        this.approvedReportsSubject.next(approvedSeed);
        this.flaggedReportsSubject.next(flaggedSeed);
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

      // Pending reports listener (status == Pending)
      const pendingReportsQuery = query(collection(db, 'reports'), where('status', '==', 'Pending'));
      this.pendingReportsUnsubscribe = onSnapshot(
        pendingReportsQuery,
        (snapshot) => {
          this.ngZone.run(() => {
            const reports = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
            this.pendingReportsSubject.next(reports);
          });
        },
        (error) => {
          console.error('=== PENDING REPORTS LISTENER ERROR ===', error);
          this.ngZone.run(() => {
            this.pendingReportsSubject.next([]);
          });
        }
      );

      // Approved reports listener (status == Approved)
      const approvedReportsQuery = query(collection(db, 'reports'), where('status', '==', 'Approved'));
      this.approvedReportsUnsubscribe = onSnapshot(
        approvedReportsQuery,
        (snapshot) => {
          this.ngZone.run(() => {
            const reports = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
            this.approvedReportsSubject.next(reports);
          });
        },
        (error) => {
          console.error('=== APPROVED REPORTS LISTENER ERROR ===', error);
          this.ngZone.run(() => {
            this.approvedReportsSubject.next([]);
          });
        }
      );

      // All reports listener (no filter)
      const reportsRef = collection(db, 'reports');
      this.reportsUnsubscribe = onSnapshot(
        reportsRef,
        (snapshot) => {
          this.ngZone.run(() => {
            const reports = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
            this.reportsSubject.next(reports);
          });
        },
        (error) => {
          console.error('=== REPORTS LISTENER ERROR ===', error);
          this.ngZone.run(() => {
            this.reportsSubject.next([]);
          });
        }
      );

      // Flagged reports listener (status == Flagged)
      const flaggedReportsQuery = query(collection(db, 'reports'), where('status', '==', 'Flagged'));
      this.flaggedReportsUnsubscribe = onSnapshot(
        flaggedReportsQuery,
        (snapshot) => {
          this.ngZone.run(() => {
            const reports = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
            this.flaggedReportsSubject.next(reports);
          });
        },
        (error) => {
          console.error('=== FLAGGED REPORTS LISTENER ERROR ===', error);
          this.ngZone.run(() => {
            this.flaggedReportsSubject.next([]);
          });
        }
      );
      
      console.log('=== LISTENERS SETUP COMPLETE ===');
      console.log('Both listeners are now active and waiting for snapshots');
    } catch (error) {
      console.error('=== CRITICAL ERROR SETTING UP LISTENERS ===', error);
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
    if (this.pendingReportsUnsubscribe) {
      this.pendingReportsUnsubscribe();
      this.pendingReportsUnsubscribe = undefined;
    }
    if (this.approvedReportsUnsubscribe) {
      this.approvedReportsUnsubscribe();
      this.approvedReportsUnsubscribe = undefined;
    }
    if (this.reportsUnsubscribe) {
      this.reportsUnsubscribe();
      this.reportsUnsubscribe = undefined;
    }
    if (this.flaggedReportsUnsubscribe) {
      this.flaggedReportsUnsubscribe();
      this.flaggedReportsUnsubscribe = undefined;
    }
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
}

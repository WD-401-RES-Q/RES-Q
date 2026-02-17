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
  onSnapshot,
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
    
    // Load initial data and set up listeners
    this.initializeData();
  }

  private async initializeData() {
    
    try {
      // Load initial data FIRST - wait for it to complete
      await this.loadInitialData();
      
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
      
      // Load pending users
      const pendingRef = collection(db, 'pending_users');
      const pendingSnapshot = await getDocs(pendingRef);
      const pendingUsers = pendingSnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));
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
        // Pending includes: pending, responding, on scene, resolved, flagged (semi-admin actions)
        const pendingSeed = reports.filter((r: any) => {
          const s = (r.status ?? '').toString().toLowerCase();
          return s === 'pending' || s === 'responding' || s === 'on scene' || s === 'resolved' || s === 'flagged';
        });
        const approvedSeed = reports.filter((r: any) => {
          const s = (r.status ?? '').toString().toLowerCase();
          return s === 'approved';
        });
        // Flagged page only shows ADMIN_FLAGGED (web admin rejections)
        const flaggedSeed = reports.filter((r: any) => (r.status ?? '').toString().toLowerCase() === 'admin_flagged');
        this.pendingReportsSubject.next(pendingSeed);
        this.approvedReportsSubject.next(approvedSeed);
        this.flaggedReportsSubject.next(flaggedSeed);
      });
      
      
      // Mark loading as complete AFTER data has been loaded
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
    
    try {
      // Pending users listener
      const pendingRef = collection(db, 'pending_users');
      
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
            
            // Always emit, even if empty
            this.pendingUsersSubject.next(users);
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
            
            // Always emit, even if empty
            this.approvedUsersSubject.next(users);
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

      // Pending reports listener (Pending, RESPONDING, ON SCENE, RESOLVED, FLAGGED - excludes ADMIN_FLAGGED)
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
      const thirtyDaysAgoTime = thirtyDaysAgo.getTime();
      
      const pendingReportsQuery = query(
        collection(db, 'reports'), 
        where('status', 'in', ['Pending', 'PENDING', 'RESPONDING', 'ON SCENE', 'RESOLVED', 'FLAGGED'])
      );
      this.pendingReportsUnsubscribe = onSnapshot(
        pendingReportsQuery,
        (snapshot) => {
          this.ngZone.run(() => {
            const reports = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })) as any[];
            // Show Pending/RESPONDING/ON SCENE always, RESOLVED/FLAGGED within 30 days
            const filtered = reports.filter(r => {
              const status = (r.status || '').toUpperCase();
              if (['PENDING', 'RESPONDING', 'ON SCENE'].includes(status)) return true;
              if (status === 'RESOLVED') {
                if (r.resolvedAt) {
                  const resolvedTime = typeof r.resolvedAt.toDate === 'function' 
                    ? r.resolvedAt.toDate().getTime() 
                    : new Date(r.resolvedAt).getTime();
                  return resolvedTime >= thirtyDaysAgoTime;
                }
                return true;
              }
              if (status === 'FLAGGED') {
                if (r.flaggedAt) {
                  const flaggedTime = typeof r.flaggedAt.toDate === 'function' 
                    ? r.flaggedAt.toDate().getTime() 
                    : new Date(r.flaggedAt).getTime();
                  return flaggedTime >= thirtyDaysAgoTime;
                }
                return true;
              }
              return false;
            });
            this.pendingReportsSubject.next(filtered);
          });
        },
        (error) => {
          console.error('=== PENDING REPORTS LISTENER ERROR ===', error);
          this.ngZone.run(() => {
            this.pendingReportsSubject.next([]);
          });
        }
      );

      // Approved reports listener (Approved status only)
      const approvedReportsQuery = query(
        collection(db, 'reports'), 
        where('status', '==', 'Approved')
      );
      this.approvedReportsUnsubscribe = onSnapshot(
        approvedReportsQuery,
        (snapshot) => {
          this.ngZone.run(() => {
            const reports = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })) as any[];
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

      // Flagged reports listener (ADMIN_FLAGGED status - only reports flagged by web admin)
      const flaggedReportsQuery = query(
        collection(db, 'reports'), 
        where('status', 'in', ['ADMIN_FLAGGED', 'Admin_Flagged'])
      );
      this.flaggedReportsUnsubscribe = onSnapshot(
        flaggedReportsQuery,
        (snapshot) => {
          this.ngZone.run(() => {
            const reports = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })) as any[];
            // Filter: show FLAGGED if within last 30 days, or if no flaggedAt (legacy data)
            const filtered = reports.filter(r => {
              if (r.flaggedAt) {
                const flaggedTime = typeof r.flaggedAt.toDate === 'function' 
                  ? r.flaggedAt.toDate().getTime() 
                  : new Date(r.flaggedAt).getTime();
                return flaggedTime >= thirtyDaysAgoTime;
              }
              // Include flagged reports without flaggedAt timestamp (legacy data)
              return true;
            });
            this.flaggedReportsSubject.next(filtered);
          });
        },
        (error) => {
          console.error('=== FLAGGED REPORTS LISTENER ERROR ===', error);
          this.ngZone.run(() => {
            this.flaggedReportsSubject.next([]);
          });
        }
      );
      
    } catch (error) {
      console.error('=== CRITICAL ERROR SETTING UP LISTENERS ===', error);
    }
  }

  // Get all documents from a collection
  async getCollection(collectionName: string): Promise<any[]> {
    try {
      const collectionRef = collection(db, collectionName);
      
      const querySnapshot = await getDocs(collectionRef);
      
      const results = querySnapshot.docs.map(doc => {
        const data = { id: doc.id, ...doc.data() };
        return data;
      });
      
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

  async deleteReportAsAdmin(
    reportId: string,
    adminId: string,
  ): Promise<{
    success: boolean;
    reportId: string;
    mediaDeleted: boolean;
    deletedCommentDocs: number;
    deletedVoteRecordDocs: number;
  }> {
    const callable = httpsCallable(functions, 'deleteReportAsAdmin');
    const result = await callable({ reportId, adminId });
    return result.data as {
      success: boolean;
      reportId: string;
      mediaDeleted: boolean;
      deletedCommentDocs: number;
      deletedVoteRecordDocs: number;
    };
  }

  async deleteAnnouncementAsAdmin(
    announcementId: string,
    adminId: string,
  ): Promise<{
    success: boolean;
    announcementId: string;
    mediaDeleted: boolean;
  }> {
    const callable = httpsCallable(functions, 'deleteAnnouncementAsAdmin');
    const result = await callable({ announcementId, adminId });
    return result.data as {
      success: boolean;
      announcementId: string;
      mediaDeleted: boolean;
    };
  }

  // Account approval methods
  async approvePendingUser(user: any, adminUsername: string) {
    try {
      const { id, ...data } = user;
      const createdAt = data['createdAt'] || Timestamp.now();


      // STEP 1: Move pending user into approved_users collection FIRST
      await setDoc(doc(db, 'approved_users', id), {
        ...data,
        createdAt,
        accountStatus: 'approved',
        approvedAt: Timestamp.now(),
        approvedBy: adminUsername,
        updatedAt: Timestamp.now()
      });


      // STEP 2: Only delete from pending after successful save
      await deleteDoc(doc(db, 'pending_users', id));
      
    } catch (error: any) {
      console.error('FAILED: Error in approvePendingUser:', error);
      console.error('Error code:', error.code);
      console.error('Error message:', error.message);
      throw new Error(`Failed to approve user: ${error.message || 'Unknown error'}`);
    }
  }

  async rejectPendingUser(user: any, reason?: string) {
    try {
      const { id } = user;
      

      // Simply delete from pending_users collection
      // No need to move to another collection
      await deleteDoc(doc(db, 'pending_users', id));
      
    } catch (error: any) {
      console.error('FAILED: Error in rejectPendingUser:', error);
      console.error('Error code:', error.code);
      console.error('Error message:', error.message);
      throw new Error(`Failed to reject user: ${error.message || 'Unknown error'}`);
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

}

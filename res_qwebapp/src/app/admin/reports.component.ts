import { Component, OnDestroy, OnInit, NgZone, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { FirestoreService } from '../firestore.service';
import { FirebaseStorageService } from '../firebase-storage.service';
import { Subscription } from 'rxjs';
import { collection, onSnapshot, orderBy, query, where, Timestamp } from 'firebase/firestore';
import { db } from '../firebase.config';

interface Report {
  id: string;
  title: string;
  category: string;
  location: string;
  date: string;
  time: string;
  reporter: string;
  description: string;
  image: string;
  greenFlags?: number;
  redFlags?: number;
  comments?: number;
  status: 'Pending' | 'Approved' | 'Flagged';
  approvedBy?: string;
  approvedAt?: string;
  respondingAt?: string;
  respondingBy?: string;
  arrivedAt?: string;
  arrivedBy?: string;
  resolvedAt?: string;
  resolvedBy?: string;
  flaggedAt?: string;
  flaggedBy?: string;
}

interface Comment {
  id: string;
  text: string;
  author: string;
  timestamp: Date;
  greenFlags: number;
  redFlags: number;
  reportId: string;
  reportTitle: string;
  reportStatus: string;
}

type FilterType = 'pending' | 'approved' | 'flagged';

@Component({
  selector: 'app-reports',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './reports.html',
})
export class ReportsComponent implements OnInit, OnDestroy {
  constructor(
    private firestoreService: FirestoreService,
    private firebaseStorageService: FirebaseStorageService,
    private ngZone: NgZone,
    private cdr: ChangeDetectorRef
  ) {}

  // Filter state
  currentFilter: FilterType = 'pending';
  showFilterDropdown = false;
  
  // All reports data
  allReports: Report[] = [];
  pendingReports: Report[] = [];
  approvedReports: Report[] = [];
  flaggedReports: Report[] = [];
  
  isLoading = true;
  private subscriptions: Subscription[] = [];

  // Modal state
  showApproveModal = false;
  showRejectModal = false;
  showRevertModal = false;
  reportToApprove: Report | null = null;
  reportToReject: Report | null = null;
  reportToRevert: Report | null = null;

  // Comments state
  expandedReportId: string | null = null;
  reportComments: { [key: string]: Comment[] } = {};
  loadingComments: { [key: string]: boolean } = {};

  // Computed property for filtered reports
  get filteredReports(): Report[] {
    switch (this.currentFilter) {
      case 'approved':
        return this.approvedReports;
      case 'flagged':
        return this.flaggedReports;
      case 'pending':
      default:
        return this.pendingReports;
    }
  }

  ngOnInit() {
    this.loadReports();
  }

  private formatTimestamp(timestamp: any): string {
    if (!timestamp) return '';
    try {
      const date = typeof timestamp.toDate === 'function' ? timestamp.toDate() : new Date(timestamp);
      if (isNaN(date.getTime())) return '';
      return date.toLocaleString('en-US', { 
        month: 'short', 
        day: 'numeric', 
        hour: 'numeric', 
        minute: '2-digit',
        hour12: true 
      });
    } catch {
      return '';
    }
  }

  ngOnDestroy() {
    this.subscriptions.forEach(sub => sub.unsubscribe());
  }

  private loadReports() {
    // Subscribe to pending reports
    const pendingSub = this.firestoreService.pendingReports$.subscribe({
      next: (docs) => {
        this.pendingReports = docs.map((doc: any) => this.mapReport(doc, 'Pending'));
        this.updateLoading();
      },
      error: (err) => {
        console.error('Failed to load pending reports:', err);
        this.pendingReports = [];
        this.updateLoading();
      },
    });

    // Subscribe to approved reports
    const approvedSub = this.firestoreService.approvedReports$.subscribe({
      next: (docs) => {
        this.approvedReports = docs.map((doc: any) => this.mapReport(doc, 'Approved'));
        this.updateLoading();
      },
      error: (err) => {
        console.error('Failed to load approved reports:', err);
        this.approvedReports = [];
        this.updateLoading();
      },
    });

    // Subscribe to flagged reports
    const flaggedSub = this.firestoreService.flaggedReports$.subscribe({
      next: (docs) => {
        this.flaggedReports = docs.map((doc: any) => this.mapReport(doc, 'Flagged'));
        this.updateLoading();
      },
      error: (err) => {
        console.error('Failed to load flagged reports:', err);
        this.flaggedReports = [];
        this.updateLoading();
      },
    });

    this.subscriptions.push(pendingSub, approvedSub, flaggedSub);
  }

  private updateLoading() {
    // Loading is complete when we have at least attempted to load all three streams
    this.isLoading = false;
    this.cdr.markForCheck();
  }

  private mapReport(doc: any, status: 'Pending' | 'Approved' | 'Flagged'): Report {
    const reportedAt = doc.reportedAt || doc.createdAt || doc.timestamp;
    const dateObj = this.coerceDate(reportedAt);
    const [dateStr, timeStr] = this.formatDateTime(dateObj);

    // Normalize location display
    let locationStr = 'Unknown location';
    if (doc.location) {
      if (typeof doc.location === 'string') {
        locationStr = doc.location;
      } else if (doc.location.address) {
        locationStr = doc.location.address;
      } else if (doc.location.lat && doc.location.lng) {
        locationStr = `${doc.location.lat}, ${doc.location.lng}`;
      }
    }

    return {
      id: doc.id ?? '',
      title: doc.incidentType ?? doc.title ?? 'Incident',
      category: doc.incidentType ?? 'Uncategorized',
      location: locationStr,
      date: dateStr,
      time: timeStr,
      reporter: doc.name ?? doc.reporter ?? 'Unknown reporter',
      description: doc.details ?? doc.description ?? 'No description provided.',
      image: this.firebaseStorageService.getDownloadUrl(doc.mediaUrl),
      greenFlags: doc.greenFlags ?? 0,
      redFlags: doc.redFlags ?? 0,
      comments: doc.comments ?? 0,
      status: status,
      approvedBy: doc.approvedBy ?? undefined,
      approvedAt: doc.approvedAt ? this.formatTimestamp(doc.approvedAt) : undefined,
      respondingAt: doc.respondingAt ? this.formatTimestamp(doc.respondingAt) : undefined,
      respondingBy: doc.respondingBy ?? undefined,
      arrivedAt: doc.arrivedAt ? this.formatTimestamp(doc.arrivedAt) : undefined,
      arrivedBy: doc.arrivedBy ?? undefined,
      resolvedAt: doc.resolvedAt ? this.formatTimestamp(doc.resolvedAt) : undefined,
      resolvedBy: doc.resolvedBy ?? undefined,
      flaggedAt: doc.flaggedAt ? this.formatTimestamp(doc.flaggedAt) : undefined,
      flaggedBy: doc.flaggedBy ?? undefined,
    };
  }

  private coerceDate(value: any): Date | null {
    if (!value) return null;
    if (typeof value.toDate === 'function') return value.toDate() as Date;
    const parsed = new Date(value);
    return isNaN(parsed.getTime()) ? null : parsed;
  }

  private formatDateTime(date: Date | null): [string, string] {
    if (!date) return ['–', '–'];
    const options: Intl.DateTimeFormatOptions = { month: 'short', day: 'numeric', year: 'numeric' };
    const timeOptions: Intl.DateTimeFormatOptions = { hour: 'numeric', minute: '2-digit', hour12: true };
    return [date.toLocaleDateString(undefined, options), date.toLocaleTimeString(undefined, timeOptions)];
  }

  // Filter switching
  toggleFilterDropdown() {
    this.showFilterDropdown = !this.showFilterDropdown;
  }

  selectFilter(filter: FilterType) {
    this.currentFilter = filter;
    this.showFilterDropdown = false;
    this.cdr.markForCheck();
  }

  // Approval actions (pending → approved)
  approve(report: Report) {
    if (report.status !== 'Pending') return;
    this.reportToApprove = report;
    this.showApproveModal = true;
  }

  confirmApprove() {
    if (!this.reportToApprove || !this.reportToApprove.id) {
      console.error('Missing report id, cannot approve');
      this.cancelApprove();
      return;
    }

    const adminName = localStorage.getItem('adminName') || 'Admin';

    this.firestoreService
      .updateDocument('reports', this.reportToApprove.id, { 
        status: 'Approved',
        approvedBy: adminName,
        approvedAt: new Date()
      })
      .catch((err) => {
        console.error('Failed to approve report:', err);
      });
    
    this.cancelApprove();
  }

  cancelApprove() {
    this.showApproveModal = false;
    this.reportToApprove = null;
  }

  // Reject/flag actions (pending → flagged)
  reject(report: Report) {
    if (report.status !== 'Pending') return;
    this.reportToReject = report;
    this.showRejectModal = true;
  }

  confirmReject() {
    if (!this.reportToReject || !this.reportToReject.id) {
      console.error('Missing report id, cannot reject');
      this.cancelReject();
      return;
    }

    this.firestoreService
      .updateDocument('reports', this.reportToReject.id, { status: 'Flagged' })
      .catch((err) => {
        console.error('Failed to reject report:', err);
      });
    
    this.cancelReject();
  }

  cancelReject() {
    this.showRejectModal = false;
    this.reportToReject = null;
  }

  // Revert actions (approved/flagged → pending)
  revert(report: Report) {
    if (report.status === 'Pending') return;
    this.reportToRevert = report;
    this.showRevertModal = true;
  }

  confirmRevert() {
    if (!this.reportToRevert || !this.reportToRevert.id) {
      console.error('Missing report id, cannot revert');
      this.cancelRevert();
      return;
    }

    this.firestoreService
      .updateDocument('reports', this.reportToRevert.id, { status: 'Pending' })
      .catch((err) => {
        console.error('Failed to revert report:', err);
      });
    
    this.cancelRevert();
  }

  cancelRevert() {
    this.showRevertModal = false;
    this.reportToRevert = null;
  }

  // Comments - load directly from Firestore
  async toggleComments(report: Report) {
    if (this.expandedReportId === report.id) {
      this.expandedReportId = null;
      this.cdr.markForCheck();
      return;
    }

    this.expandedReportId = report.id;
    this.cdr.markForCheck();
    
    if (this.reportComments[report.id]) {
      return;
    }

    this.loadingComments[report.id] = true;

    try {
    this.ngZone.runOutsideAngular(() => {
      const commentsRef = collection(db, 'reports', report.id, 'comments');
      const commentsQuery = query(commentsRef, orderBy('timestamp', 'desc'));
      onSnapshot(commentsQuery, (snapshot) => {
        const comments = snapshot.docs.map(doc => this.mapComment(doc, report.id));

        this.ngZone.run(() => {
          this.reportComments[report.id] = comments;
          this.loadingComments[report.id] = false;
          this.cdr.markForCheck();
        });
      });
    });
    } catch (err) {
      console.error('Error loading comments:', err);
      this.ngZone.run(() => {
        this.loadingComments[report.id] = false;
        this.reportComments[report.id] = [];
        this.cdr.markForCheck();
      });
    }
  }

  private mapComment(doc: any, reportId: string): Comment {
    const data = doc.data();
    const timestamp = data.timestamp;
    let timestampDate: Date;

    if (timestamp && typeof timestamp.toDate === 'function') {
      timestampDate = timestamp.toDate();
    } else {
      timestampDate = new Date(timestamp);
    }

    return {
      id: doc.id,
      text: data.text || '',
      author: data.author || 'Anonymous',
      timestamp: timestampDate,
      greenFlags: data.greenFlags || 0,
      redFlags: data.redFlags || 0,
      reportId: data.reportId || reportId,
      reportTitle: data.reportTitle || '',
      reportStatus: data.reportStatus || '',
    };
  }

  formatCommentTime(timestamp: Date): string {
    if (!(timestamp instanceof Date)) {
      return '–';
    }
    const now = new Date();
    const diff = now.getTime() - timestamp.getTime();
    const minutes = Math.floor(diff / 60000);
    const hours = Math.floor(diff / 3600000);
    const days = Math.floor(diff / 86400000);

    if (minutes < 60) return `${minutes}m ago`;
    if (hours < 24) return `${hours}h ago`;
    if (days < 7) return `${days}d ago`;

    return timestamp.toLocaleDateString();
  }
}

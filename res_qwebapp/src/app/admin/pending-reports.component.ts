import { Component, OnDestroy, OnInit, NgZone, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FirestoreService } from '../firestore.service';
import { Subscription } from 'rxjs';
import { collection, getDocs, query, orderBy, Timestamp } from 'firebase/firestore';
import { db } from '../firebase.config';

interface PendingReport {
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

@Component({
  selector: 'app-pending-reports',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './pending-reports.html',
})
export class PendingReportsComponent implements OnInit, OnDestroy {
  constructor(
    private firestoreService: FirestoreService,
    private ngZone: NgZone,
    private cdr: ChangeDetectorRef
  ) {}

  reports: PendingReport[] = [];
  isLoading = true;
  private sub?: Subscription;

  // Modal state
  showApproveModal = false;
  showRejectModal = false;
  reportToApprove: PendingReport | null = null;
  reportToReject: PendingReport | null = null;

  // Comments state
  expandedReportId: string | null = null;
  reportComments: { [key: string]: Comment[] } = {};
  loadingComments: { [key: string]: boolean } = {};

  async ngOnInit() {
    // Subscribe to shared pending reports stream (persists across navigation)
    this.sub = this.firestoreService.pendingReports$.subscribe({
      next: (docs) => {
        this.reports = docs.map((doc: any) => this.mapReport(doc));
        this.isLoading = false;
      },
      error: (err) => {
        console.error('Failed to listen to pending reports:', err);
        this.reports = [];
        this.isLoading = false;
      },
    });
  }

  ngOnDestroy() {
    if (this.sub) {
      this.sub.unsubscribe();
    }
  }

  private mapReport(doc: any): PendingReport {
    const reportedAt = doc.reportedAt || doc.createdAt || doc.timestamp;
    const dateObj = this.coerceDate(reportedAt);
    const [dateStr, timeStr] = this.formatDateTime(dateObj);

    return {
      id: doc.id ?? '',
      title: doc.incidentType ?? doc.title ?? 'Incident',
      category: doc.incidentType ?? 'Uncategorized',
      location: doc.location?.address ?? doc.location ?? 'Unknown location',
      date: dateStr,
      time: timeStr,
      reporter: doc.name ?? doc.reporter ?? 'Unknown reporter',
      description: doc.details ?? doc.description ?? 'No description provided.',
      image: doc.mediaUrl ?? 'assets/images/placeholder-report.jpg',
      greenFlags: doc.greenFlags ?? 0,
      redFlags: doc.redFlags ?? 0,
      comments: doc.comments ?? 0,
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

  approve(report: PendingReport) {
    this.reportToApprove = report;
    this.showApproveModal = true;
  }

  confirmApprove() {
    if (!this.reportToApprove || !this.reportToApprove.id) {
      console.error('Missing report id, cannot approve');
      this.cancelApprove();
      return;
    }

    // Optimistically mark as approved; real-time listener will remove it from pending list
    this.firestoreService
      .updateDocument('reports', this.reportToApprove.id, { status: 'Approved' })
      .catch((err) => {
        console.error('Failed to approve report:', err);
      });
    
    this.cancelApprove();
  }

  cancelApprove() {
    this.showApproveModal = false;
    this.reportToApprove = null;
  }

  reject(report: PendingReport) {
    this.reportToReject = report;
    this.showRejectModal = true;
  }

  confirmReject() {
    if (!this.reportToReject || !this.reportToReject.id) {
      console.error('Missing report id, cannot flag');
      this.cancelReject();
      return;
    }

    // Move to flagged by setting status; pending listener will drop it
    this.firestoreService
      .updateDocument('reports', this.reportToReject.id, { status: 'Flagged', reason: 'Flagged by admin' })
      .catch((err) => {
        console.error('Failed to flag report:', err);
      });
    
    this.cancelReject();
  }

  cancelReject() {
    this.showRejectModal = false;
    this.reportToReject = null;
  }

  async toggleComments(report: PendingReport) {
    if (this.expandedReportId === report.id) {
      this.expandedReportId = null;
      this.cdr.markForCheck();
      return;
    }

    this.expandedReportId = report.id;
    this.cdr.markForCheck();
    
    // If already loaded, don't fetch again
    if (this.reportComments[report.id]) {
      return;
    }

    this.loadingComments[report.id] = true;
    this.cdr.markForCheck();

    this.ngZone.runOutsideAngular(async () => {
      try {
        const rootRef = collection(db, 'comments');
        const rootQuery = query(rootRef, orderBy('timestamp', 'desc'));
        const snapshot = await getDocs(rootQuery);
        
        const comments = snapshot.docs
          .map(doc => this.mapComment(doc))
          .filter(comment => comment.reportId === report.id);
        
        this.ngZone.run(() => {
          this.reportComments[report.id] = comments;
          this.loadingComments[report.id] = false;
          this.cdr.markForCheck();
        });
      } catch (error) {
        console.error('Error loading comments:', error);
        this.ngZone.run(() => {
          this.reportComments[report.id] = [];
          this.loadingComments[report.id] = false;
          this.cdr.markForCheck();
        });
      }
    });
  }

  private mapComment(doc: any): Comment {
    const data = doc.data();
    let timestamp = new Date();
    
    if (data.timestamp) {
      if (typeof data.timestamp.toDate === 'function') {
        timestamp = (data.timestamp as Timestamp).toDate();
      } else {
        timestamp = new Date(data.timestamp);
      }
    }

    return {
      id: doc.id,
      text: data.text ?? '',
      author: data.author ?? 'Anonymous',
      timestamp: timestamp,
      greenFlags: data.greenFlags ?? 0,
      redFlags: data.redFlags ?? 0,
      reportId: data.reportId ?? '',
      reportTitle: data.reportTitle ?? '',
      reportStatus: data.reportStatus ?? ''
    };
  }

  formatCommentTime(date: Date): string {
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const minutes = Math.floor(diff / 60000);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);

    if (minutes < 1) return 'Just now';
    if (minutes < 60) return `${minutes}m ago`;
    if (hours < 24) return `${hours}h ago`;
    if (days < 7) return `${days}d ago`;
    return date.toLocaleDateString();
  }
}

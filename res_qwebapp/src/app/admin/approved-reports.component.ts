import { Component, OnDestroy, OnInit, NgZone, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FirestoreService } from '../firestore.service';
import { FirebaseStorageService } from '../firebase-storage.service';
import { Subscription } from 'rxjs';
import { collection, getDocs, query, orderBy, Timestamp } from 'firebase/firestore';
import { db } from '../firebase.config';

interface ApprovedReport {
  id: string;
  category: string;
  type: string;
  location: string;
  approvedBy: string;
  date: string;
  time: string;
  imageUrl: string;
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
  selector: 'app-approved-reports',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './approved-reports.html',
})
export class ApprovedReportsComponent implements OnInit, OnDestroy {
  constructor(
    private firestoreService: FirestoreService,
    private firebaseStorageService: FirebaseStorageService,
    private ngZone: NgZone,
    private cdr: ChangeDetectorRef
  ) {}

  reports: ApprovedReport[] = [];
  isLoading = true;
  private sub?: Subscription;

  // Modal state
  showRevertModal = false;
  reportToRevert: ApprovedReport | null = null;

  // Comments state
  expandedReportId: string | null = null;
  reportComments: { [key: string]: Comment[] } = {};
  loadingComments: { [key: string]: boolean } = {};

  ngOnInit(): void {
    this.sub = this.firestoreService.approvedReports$.subscribe({
      next: (docs) => {
        this.reports = docs.map((doc: any) => this.mapReport(doc));
        this.isLoading = false;
      },
      error: (err) => {
        console.error('Failed to load approved reports:', err);
        this.reports = [];
        this.isLoading = false;
      },
    });
  }

  ngOnDestroy(): void {
    if (this.sub) this.sub.unsubscribe();
  }

  private mapReport(doc: any): ApprovedReport {
    const reportedAt = doc.reportedAt || doc.createdAt || doc.timestamp;
    const dateObj = this.coerceDate(reportedAt);
    const [dateStr, timeStr] = this.formatDateTime(dateObj);

    // Fix location display
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
      category: doc.incidentType ?? 'Category',
      type: doc.type ?? doc.incidentType ?? 'Type',
      location: locationStr,
      approvedBy: doc.approvedBy ?? 'Admin',
      date: dateStr,
      time: timeStr,
      imageUrl: this.firebaseStorageService.getDownloadUrl(doc.mediaUrl),
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

  revert(report: ApprovedReport) {
    this.reportToRevert = report;
    this.showRevertModal = true;
  }

  confirmRevert() {
    if (!this.reportToRevert) {
      this.cancelRevert();
      return;
    }
    
    // Move back to pending
    this.firestoreService
      .updateDocument('reports', this.reportToRevert.id, { status: 'Pending' })
      .catch((err) => console.error('Failed to revert approved report:', err));
    
    this.cancelRevert();
  }

  cancelRevert() {
    this.showRevertModal = false;
    this.reportToRevert = null;
  }

  async toggleComments(report: ApprovedReport) {
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

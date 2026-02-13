import { Component, OnDestroy, OnInit, NgZone, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { FirestoreService } from '../../../core/services/firestore.service';
import { FirebaseStorageService } from '../../../core/services/firebase-storage.service';
import { Subscription } from 'rxjs';
import { collection, onSnapshot, orderBy, query, where, Timestamp } from 'firebase/firestore';
import { db } from '../../../core/config/firebase.config';

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
  mediaType?: 'photo' | 'video';
  greenFlags?: number;
  redFlags?: number;
  comments?: number;
  status: 'Pending' | 'Approved' | 'Flagged';
  incidentStatus?: string;
  sortTimestamp?: number;
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
type DateFilterType = 'all' | 'today' | 'week' | 'month' | 'year';
type IncidentFilterType = 'all' | 'fire' | 'flood' | 'vehicular' | 'earthquake' | 'other';

@Component({
  selector: 'app-reports',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './reports.html',
  styleUrls: ['./reports.component.scss'],
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

  // Date filter state
  dateFilter: DateFilterType = 'all';
  showDateDropdown = false;

  // Incident type filter state
  incidentFilter: IncidentFilterType = 'all';
  showIncidentDropdown = false;
  
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

  // Media viewer state
  showMediaViewer = false;
  activeMediaUrl = '';
  activeMediaTitle = 'Report media';
  activeMediaType: 'photo' | 'video' = 'photo';

  // Computed property for filtered reports
  get filteredReports(): Report[] {
    let reports: Report[];
    switch (this.currentFilter) {
      case 'approved':
        reports = this.approvedReports;
        break;
      case 'flagged':
        reports = this.flaggedReports;
        break;
      case 'pending':
      default:
        reports = this.pendingReports;
        break;
    }

    // Apply date filter
    if (this.dateFilter !== 'all') {
      reports = this.applyDateFilter(reports);
    }

    // Apply incident type filter
    if (this.incidentFilter !== 'all') {
      reports = this.applyIncidentFilter(reports);
    }

    if (this.dateFilter === 'all') {
      reports = [...reports].sort(
        (a, b) => (b.sortTimestamp ?? 0) - (a.sortTimestamp ?? 0)
      );
    }

    return reports;
  }

  private applyDateFilter(reports: Report[]): Report[] {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    return reports.filter(report => {
      const reportDate = this.parseReportDate(report.date);
      if (!reportDate) return true;

      switch (this.dateFilter) {
        case 'today':
          return reportDate >= today;
        case 'week':
          const weekAgo = new Date(today);
          weekAgo.setDate(weekAgo.getDate() - 7);
          return reportDate >= weekAgo;
        case 'month':
          const monthAgo = new Date(today);
          monthAgo.setMonth(monthAgo.getMonth() - 1);
          return reportDate >= monthAgo;
        case 'year':
          const yearAgo = new Date(today);
          yearAgo.setFullYear(yearAgo.getFullYear() - 1);
          return reportDate >= yearAgo;
        default:
          return true;
      }
    });
  }

  private applyIncidentFilter(reports: Report[]): Report[] {
    return reports.filter(report => {
      const category = (report.category || '').toLowerCase();
      switch (this.incidentFilter) {
        case 'fire':
          return category.includes('fire');
        case 'flood':
          return category.includes('flood');
        case 'vehicular':
          return category.includes('vehicular') || category.includes('accident');
        case 'earthquake':
          return category.includes('earthquake');
        case 'other':
          return !category.includes('fire') &&
                 !category.includes('flood') &&
                 !category.includes('vehicular') &&
                 !category.includes('accident') &&
                 !category.includes('earthquake');
        default:
          return true;
      }
    });
  }

  private parseReportDate(dateStr: string): Date | null {
    if (!dateStr || dateStr === '–') return null;
    const parsed = new Date(dateStr);
    return isNaN(parsed.getTime()) ? null : parsed;
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

  private valueOrDash(value?: string | null): string {
    const normalized = (value ?? '').toString().trim();
    return normalized.length > 0 ? normalized : '-';
  }

  getActivityResponder(report: Report): string {
    return this.valueOrDash(
      report.respondingBy ??
          report.arrivedBy ??
          report.resolvedBy ??
          report.flaggedBy,
    );
  }

  getActivityTime(value?: string): string {
    return this.valueOrDash(value);
  }

  getFinalActivityLabel(report: Report): string {
    const status = (report.incidentStatus ?? report.status ?? '').toUpperCase();
    return status === 'FLAGGED'
      ? 'Time Flagged:'
      : 'Time Approved:';
  }

  getFinalActivityTime(report: Report): string {
    const status = (report.incidentStatus ?? report.status ?? '').toUpperCase();
    const isFlagged = status === 'FLAGGED';
    if (isFlagged) {
      return this.valueOrDash(report.flaggedAt);
    }
    return this.valueOrDash(report.resolvedAt ?? report.approvedAt);
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
    const sortTimestamp = dateObj ? dateObj.getTime() : 0;
    const mediaUrl = this.firebaseStorageService.getDownloadUrl(doc.mediaUrl);
    const mediaType = this.resolveMediaType(doc.mediaType, mediaUrl);

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
      image: mediaUrl,
      mediaType,
      greenFlags: doc.greenFlags ?? 0,
      redFlags: doc.redFlags ?? 0,
      comments: doc.comments ?? 0,
      status: status,
      incidentStatus: (doc.status ?? '').toString().toUpperCase(),
      sortTimestamp,
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

  isVideoMedia(report: Report): boolean {
    return this.resolveMediaType(report.mediaType, report.image) === 'video';
  }

  openMediaViewer(report: Report) {
    const mediaUrl = (report.image ?? '').toString().trim();
    if (!mediaUrl) return;

    this.activeMediaUrl = mediaUrl;
    this.activeMediaType = this.resolveMediaType(report.mediaType, mediaUrl);
    this.activeMediaTitle = (report.title ?? 'Report media').toString().trim() || 'Report media';
    this.showMediaViewer = true;
    this.cdr.markForCheck();
  }

  closeMediaViewer() {
    this.showMediaViewer = false;
    this.activeMediaUrl = '';
    this.activeMediaTitle = 'Report media';
    this.activeMediaType = 'photo';
    this.cdr.markForCheck();
  }

  private resolveMediaType(rawType: unknown, mediaUrl: string): 'photo' | 'video' {
    const normalizedType = (rawType ?? '').toString().trim().toLowerCase();
    if (normalizedType.includes('video')) return 'video';
    if (normalizedType.includes('photo') || normalizedType.includes('image')) return 'photo';

    const normalizedUrl = (mediaUrl ?? '').toString().toLowerCase();
    if (
      /\.(mp4|mov|webm|m4v|ogg)(\?|$)/.test(normalizedUrl) ||
      normalizedUrl.includes('video%2f')
    ) {
      return 'video';
    }

    return 'photo';
  }

  // Filter switching
  toggleFilterDropdown() {
    this.showFilterDropdown = !this.showFilterDropdown;
    this.showDateDropdown = false;
    this.showIncidentDropdown = false;
  }

  selectFilter(filter: FilterType) {
    this.currentFilter = filter;
    this.showFilterDropdown = false;
    this.cdr.markForCheck();
  }

  // Date filter methods
  toggleDateDropdown() {
    this.showDateDropdown = !this.showDateDropdown;
    this.showFilterDropdown = false;
    this.showIncidentDropdown = false;
  }

  selectDateFilter(filter: DateFilterType) {
    this.dateFilter = filter;
    this.showDateDropdown = false;
    this.cdr.markForCheck();
  }

  getDateFilterLabel(): string {
    const labels: Record<DateFilterType, string> = {
      'all': 'ALL TIME',
      'today': 'TODAY',
      'week': 'THIS WEEK',
      'month': 'THIS MONTH',
      'year': 'THIS YEAR'
    };
    return labels[this.dateFilter];
  }

  // Incident type filter methods
  toggleIncidentDropdown() {
    this.showIncidentDropdown = !this.showIncidentDropdown;
    this.showFilterDropdown = false;
    this.showDateDropdown = false;
  }

  selectIncidentFilter(filter: IncidentFilterType) {
    this.incidentFilter = filter;
    this.showIncidentDropdown = false;
    this.cdr.markForCheck();
  }

  getIncidentFilterLabel(): string {
    const labels: Record<IncidentFilterType, string> = {
      'all': 'ALL TYPES',
      'fire': 'FIRE',
      'flood': 'FLOOD',
      'vehicular': 'VEHICULAR',
      'earthquake': 'EARTHQUAKE',
      'other': 'OTHER'
    };
    return labels[this.incidentFilter];
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

    const adminName = localStorage.getItem('adminName') || 'Admin';

    this.firestoreService
      .updateDocument('reports', this.reportToReject.id, {
        status: 'ADMIN_FLAGGED',
        flaggedAt: new Date(),
        flaggedBy: adminName
      })
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

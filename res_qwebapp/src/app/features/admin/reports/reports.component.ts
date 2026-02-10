import { Component, OnDestroy, OnInit, NgZone, ChangeDetectorRef, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { FirestoreService } from '../../../core/services/firestore.service';
import { FirebaseStorageService } from '../../../core/services/firebase-storage.service';
import { Subscription } from 'rxjs';
import {
  collection,
  getDocs,
  limit,
  onSnapshot,
  orderBy,
  query,
  startAfter,
  type Unsubscribe,
} from 'firebase/firestore';
import { db } from '../../../core/config/firebase.config';
import { ReportCardComponent } from './report-card/report-card.component';
import {
  Comment,
  DateFilterType,
  FilterType,
  IncidentFilterType,
  Report,
} from './reports.models';

@Component({
  selector: 'app-reports',
  standalone: true,
  imports: [CommonModule, FormsModule, ReportCardComponent],
  templateUrl: './reports.html',
  styleUrls: ['./reports.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush,
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

  readonly dateFilterLabels: Record<DateFilterType, string> = {
    all: 'ALL TIME',
    today: 'TODAY',
    week: 'THIS WEEK',
    month: 'THIS MONTH',
    year: 'THIS YEAR',
  };

  readonly incidentFilterLabels: Record<IncidentFilterType, string> = {
    all: 'ALL TYPES',
    fire: 'FIRE',
    flood: 'FLOOD',
    vehicular: 'VEHICULAR',
    earthquake: 'EARTHQUAKE',
    other: 'OTHER',
  };
  
  // All reports data
  allReports: Report[] = [];
  pendingReports: Report[] = [];
  approvedReports: Report[] = [];
  flaggedReports: Report[] = [];
  filteredReports: Report[] = [];
  visibleReports: Report[] = [];
  hasMoreReports = false;
  hasMoreServerReports = true;
  isLoadingMoreReports = false;
  private readonly initialVisibleReports = 20;
  private readonly visibleReportsStep = 20;
  private visibleReportsCount = 0;
  
  isLoading = true;
  private subscriptions: Subscription[] = [];
  private hasLoadedPending = false;
  private hasLoadedApproved = false;
  private hasLoadedFlagged = false;
  private streamRecomputeScheduled = false;
  private streamRecomputeHandle: number | null = null;

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
  private liveReportComments: { [key: string]: Comment[] } = {};
  private pagedReportComments: { [key: string]: Comment[] } = {};
  visibleReportComments: { [key: string]: Comment[] } = {};
  hasMoreComments: { [key: string]: boolean } = {};
  private hasMoreServerComments: { [key: string]: boolean } = {};
  loadingComments: { [key: string]: boolean } = {};
  loadingMoreComments: { [key: string]: boolean } = {};
  private commentUnsubscribers: { [key: string]: Unsubscribe } = {};
  private commentPageCursors: { [key: string]: any | null } = {};
  private visibleCommentCounts: { [key: string]: number } = {};
  private readonly initialVisibleComments = 30;
  private readonly visibleCommentsStep = 30;
  private readonly initialCommentsServerPageSize = 50;
  private readonly commentsServerPageSize = 50;
  private readonly maxCachedCommentReports = 12;
  private commentCacheOrder: string[] = [];

  // Recompute filtered reports only when source lists or filters change.
  private recomputeFilteredReports(resetVisibleWindow = false) {
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

    this.filteredReports = reports;
    this.syncVisibleReports(resetVisibleWindow);
  }

  private syncVisibleReports(resetVisibleWindow = false): void {
    if (resetVisibleWindow || this.visibleReportsCount <= 0) {
      this.visibleReportsCount = this.initialVisibleReports;
    }

    this.visibleReportsCount = Math.min(this.visibleReportsCount, this.filteredReports.length);
    this.visibleReports = this.filteredReports.slice(0, this.visibleReportsCount);
    this.hasMoreReports = this.visibleReportsCount < this.filteredReports.length;

    if (this.expandedReportId && !this.visibleReports.some((report) => report.id === this.expandedReportId)) {
      const expandedReportId = this.expandedReportId;
      this.expandedReportId = null;
      this.loadingComments[expandedReportId] = false;
      this.detachCommentListener(expandedReportId);
    }
  }

  get canLoadMoreReports(): boolean {
    return this.hasMoreReports || this.hasMoreServerReports;
  }

  async showMoreReports(): Promise<void> {
    const nextVisibleCount = Math.min(
      this.visibleReportsCount + this.visibleReportsStep,
      this.filteredReports.length,
    );

    if (nextVisibleCount > this.visibleReports.length) {
      this.visibleReportsCount = nextVisibleCount;
      this.syncVisibleReports();
      this.cdr.markForCheck();
      return;
    }

    if (!this.hasMoreServerReports || this.isLoadingMoreReports) {
      this.cdr.markForCheck();
      return;
    }

    this.isLoadingMoreReports = true;
    this.cdr.markForCheck();

    try {
      await this.firestoreService.loadMoreReportsPage();
      this.recomputeFilteredReports();
      const grownVisibleCount = Math.min(
        this.visibleReportsCount + this.visibleReportsStep,
        this.filteredReports.length,
      );
      this.visibleReportsCount = grownVisibleCount;
      this.syncVisibleReports();
    } catch (err) {
      console.error('Failed to load more reports:', err);
    } finally {
      this.isLoadingMoreReports = false;
      this.cdr.markForCheck();
    }
  }

  private syncVisibleComments(reportId: string, resetVisibleWindow = false): void {
    const comments = this.reportComments[reportId] ?? [];

    if (resetVisibleWindow || !this.visibleCommentCounts[reportId]) {
      this.visibleCommentCounts[reportId] = this.initialVisibleComments;
    }

    const visibleCount = Math.min(this.visibleCommentCounts[reportId], comments.length);
    this.visibleCommentCounts[reportId] = visibleCount;
    this.visibleReportComments[reportId] = comments.slice(0, visibleCount);
    this.hasMoreComments[reportId] =
      visibleCount < comments.length || this.hasMoreServerComments[reportId] === true;
  }

  async showMoreComments(reportId: string): Promise<void> {
    if (!reportId) return;
    this.touchCommentCache(reportId);

    const visibleCount = this.visibleReportComments[reportId]?.length ?? 0;
    const loadedCount = this.reportComments[reportId]?.length ?? 0;

    if (visibleCount < loadedCount) {
      const currentCount = this.visibleCommentCounts[reportId] ?? this.initialVisibleComments;
      this.visibleCommentCounts[reportId] = currentCount + this.visibleCommentsStep;
      this.syncVisibleComments(reportId);
      this.cdr.markForCheck();
      return;
    }

    if (!this.hasMoreServerComments[reportId] || this.loadingMoreComments[reportId]) {
      this.syncVisibleComments(reportId);
      this.cdr.markForCheck();
      return;
    }

    await this.loadMoreCommentsFromServer(reportId);
  }

  private mergeCommentLists(primary: Comment[], secondary: Comment[]): Comment[] {
    const merged: Comment[] = [];
    const seen = new Set<string>();

    for (const comment of primary) {
      if (seen.has(comment.id)) continue;
      seen.add(comment.id);
      merged.push(comment);
    }

    for (const comment of secondary) {
      if (seen.has(comment.id)) continue;
      seen.add(comment.id);
      merged.push(comment);
    }

    return merged;
  }

  private touchCommentCache(reportId: string): void {
    this.commentCacheOrder = this.commentCacheOrder.filter((id) => id !== reportId);
    this.commentCacheOrder.push(reportId);
    this.trimCommentCache();
  }

  private trimCommentCache(): void {
    let safetyCounter = 0;
    while (this.commentCacheOrder.length > this.maxCachedCommentReports && safetyCounter < 50) {
      safetyCounter += 1;
      const candidate = this.commentCacheOrder.shift();
      if (!candidate) break;

      if (candidate === this.expandedReportId) {
        this.commentCacheOrder.push(candidate);
        continue;
      }

      this.evictCommentCache(candidate);
    }
  }

  private evictCommentCache(reportId: string): void {
    this.detachCommentListener(reportId);

    delete this.reportComments[reportId];
    delete this.liveReportComments[reportId];
    delete this.pagedReportComments[reportId];
    delete this.visibleReportComments[reportId];
    delete this.hasMoreComments[reportId];
    delete this.hasMoreServerComments[reportId];
    delete this.loadingComments[reportId];
    delete this.loadingMoreComments[reportId];
    delete this.commentPageCursors[reportId];
    delete this.visibleCommentCounts[reportId];
  }

  private async loadMoreCommentsFromServer(reportId: string): Promise<void> {
    const cursor = this.commentPageCursors[reportId];
    if (!cursor) {
      this.hasMoreServerComments[reportId] = false;
      this.syncVisibleComments(reportId);
      this.cdr.markForCheck();
      return;
    }

    this.loadingMoreComments[reportId] = true;
    this.cdr.markForCheck();

    try {
      const commentsRef = collection(db, 'reports', reportId, 'comments');
      const nextPageQuery = query(
        commentsRef,
        orderBy('timestamp', 'desc'),
        startAfter(cursor),
        limit(this.commentsServerPageSize),
      );
      const snapshot = await getDocs(nextPageQuery);
      const serverComments = snapshot.docs.map((doc) => this.mapComment(doc, reportId));

      const existingPagedComments = this.pagedReportComments[reportId] ?? [];
      this.pagedReportComments[reportId] = this.mergeCommentLists(
        existingPagedComments,
        serverComments,
      );

      if (snapshot.docs.length > 0) {
        this.commentPageCursors[reportId] = snapshot.docs[snapshot.docs.length - 1];
      }
      this.hasMoreServerComments[reportId] = snapshot.docs.length === this.commentsServerPageSize;

      const liveComments = this.liveReportComments[reportId] ?? [];
      this.reportComments[reportId] = this.mergeCommentLists(
        liveComments,
        this.pagedReportComments[reportId],
      );
      this.touchCommentCache(reportId);

      const currentCount = this.visibleCommentCounts[reportId] ?? this.initialVisibleComments;
      this.visibleCommentCounts[reportId] = currentCount + this.visibleCommentsStep;
      this.syncVisibleComments(reportId);
    } catch (err) {
      console.error('Error loading more comments:', err);
      this.hasMoreServerComments[reportId] = false;
      this.syncVisibleComments(reportId);
    } finally {
      this.loadingMoreComments[reportId] = false;
      this.cdr.markForCheck();
    }
  }

  private ensureCommentState(reportId: string, resetServerPaging = false): void {
    if (resetServerPaging) {
      this.pagedReportComments[reportId] = [];
      this.liveReportComments[reportId] = [];
      this.commentPageCursors[reportId] = null;
      this.hasMoreServerComments[reportId] = false;
    }

    this.loadingMoreComments[reportId] = this.loadingMoreComments[reportId] ?? false;
    this.visibleCommentCounts[reportId] = this.visibleCommentCounts[reportId] ?? this.initialVisibleComments;
    this.visibleReportComments[reportId] = this.visibleReportComments[reportId] ?? [];
    this.reportComments[reportId] = this.reportComments[reportId] ?? [];
    this.touchCommentCache(reportId);
  }

  trackByReportId(index: number, report: Report): string {
    return report.id || `report-${index}`;
  }

  private applyDateFilter(reports: Report[]): Report[] {
    const now = new Date();
    const todayStart = new Date(
      now.getFullYear(),
      now.getMonth(),
      now.getDate(),
    );
    let threshold = todayStart.getTime();

    switch (this.dateFilter) {
      case 'today':
        threshold = todayStart.getTime();
        break;
      case 'week': {
        const weekAgo = new Date(todayStart);
        weekAgo.setDate(weekAgo.getDate() - 7);
        threshold = weekAgo.getTime();
        break;
      }
      case 'month': {
        const monthAgo = new Date(todayStart);
        monthAgo.setMonth(monthAgo.getMonth() - 1);
        threshold = monthAgo.getTime();
        break;
      }
      case 'year': {
        const yearAgo = new Date(todayStart);
        yearAgo.setFullYear(yearAgo.getFullYear() - 1);
        threshold = yearAgo.getTime();
        break;
      }
      default:
        return reports;
    }

    return reports.filter((report) => {
      const reportTimestamp = report.sortTimestamp ?? 0;
      if (reportTimestamp <= 0) return true;
      return reportTimestamp >= threshold;
    });
  }

  private applyIncidentFilter(reports: Report[]): Report[] {
    if (this.incidentFilter === 'other') {
      return reports.filter((report) => report.incidentFilterKey === 'other');
    }

    return reports.filter((report) => report.incidentFilterKey === this.incidentFilter);
  }

  private sortReportsByTimestamp(reports: Report[]): Report[] {
    return [...reports].sort((a, b) => (b.sortTimestamp ?? 0) - (a.sortTimestamp ?? 0));
  }

  private toIncidentFilterKey(categoryKey: string): Exclude<IncidentFilterType, 'all'> {
    if (categoryKey.includes('fire')) return 'fire';
    if (categoryKey.includes('flood')) return 'flood';
    if (categoryKey.includes('vehicular') || categoryKey.includes('accident')) return 'vehicular';
    if (categoryKey.includes('earthquake')) return 'earthquake';
    return 'other';
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

  ngOnDestroy() {
    this.cancelScheduledStreamRecompute();
    this.detachAllCommentListeners();
    this.subscriptions.forEach(sub => sub.unsubscribe());
  }

  private detachCommentListener(reportId: string): void {
    const unsubscribe = this.commentUnsubscribers[reportId];
    if (!unsubscribe) return;
    try {
      unsubscribe();
    } catch (err) {
      console.error('Failed to unsubscribe comments listener:', err);
    } finally {
      delete this.commentUnsubscribers[reportId];
    }
  }

  private detachAllCommentListeners(): void {
    for (const reportId of Object.keys(this.commentUnsubscribers)) {
      this.detachCommentListener(reportId);
    }
  }

  private loadReports() {
    // Subscribe to pending reports
    const pendingSub = this.firestoreService.pendingReports$.subscribe({
      next: (docs) => {
        this.pendingReports = this.sortReportsByTimestamp(
          docs.map((doc: any) => this.mapReport(doc, 'Pending')),
        );
        this.updateLoading('pending');
      },
      error: (err) => {
        console.error('Failed to load pending reports:', err);
        this.pendingReports = [];
        this.updateLoading('pending');
      },
    });

    // Subscribe to approved reports
    const approvedSub = this.firestoreService.approvedReports$.subscribe({
      next: (docs) => {
        this.approvedReports = this.sortReportsByTimestamp(
          docs.map((doc: any) => this.mapReport(doc, 'Approved')),
        );
        this.updateLoading('approved');
      },
      error: (err) => {
        console.error('Failed to load approved reports:', err);
        this.approvedReports = [];
        this.updateLoading('approved');
      },
    });

    // Subscribe to flagged reports
    const flaggedSub = this.firestoreService.flaggedReports$.subscribe({
      next: (docs) => {
        this.flaggedReports = this.sortReportsByTimestamp(
          docs.map((doc: any) => this.mapReport(doc, 'Flagged')),
        );
        this.updateLoading('flagged');
      },
      error: (err) => {
        console.error('Failed to load flagged reports:', err);
        this.flaggedReports = [];
        this.updateLoading('flagged');
      },
    });

    const hasMoreReportsSub = this.firestoreService.hasMoreReports$.subscribe({
      next: (hasMore) => {
        this.hasMoreServerReports = hasMore;
        this.cdr.markForCheck();
      },
      error: () => {
        this.hasMoreServerReports = false;
        this.cdr.markForCheck();
      },
    });

    this.subscriptions.push(pendingSub, approvedSub, flaggedSub, hasMoreReportsSub);
  }

  private updateLoading(stream: 'pending' | 'approved' | 'flagged') {
    switch (stream) {
      case 'pending':
        this.hasLoadedPending = true;
        break;
      case 'approved':
        this.hasLoadedApproved = true;
        break;
      case 'flagged':
        this.hasLoadedFlagged = true;
        break;
    }

    this.isLoading = !(this.hasLoadedPending && this.hasLoadedApproved && this.hasLoadedFlagged);
    this.scheduleStreamRecompute();
  }

  private scheduleStreamRecompute(): void {
    if (this.streamRecomputeScheduled) return;
    this.streamRecomputeScheduled = true;

    this.ngZone.runOutsideAngular(() => {
      const flush = () => {
        this.ngZone.run(() => {
          this.streamRecomputeScheduled = false;
          this.streamRecomputeHandle = null;
          this.recomputeFilteredReports();
          this.cdr.markForCheck();
        });
      };

      if (typeof requestAnimationFrame === 'function') {
        this.streamRecomputeHandle = requestAnimationFrame(() => flush());
      } else {
        this.streamRecomputeHandle = setTimeout(flush, 16) as unknown as number;
      }
    });
  }

  private cancelScheduledStreamRecompute(): void {
    if (this.streamRecomputeHandle === null) return;
    if (typeof cancelAnimationFrame === 'function') {
      cancelAnimationFrame(this.streamRecomputeHandle);
    } else {
      clearTimeout(this.streamRecomputeHandle);
    }
    this.streamRecomputeHandle = null;
    this.streamRecomputeScheduled = false;
  }

  private mapReport(doc: any, status: 'Pending' | 'Approved' | 'Flagged'): Report {
    const reportedAt = doc.reportedAt || doc.createdAt || doc.timestamp;
    const dateObj = this.coerceDate(reportedAt);
    const [dateStr, timeStr] = this.formatDateTime(dateObj);
    const sortTimestamp = dateObj ? dateObj.getTime() : 0;
    const category = doc.incidentType ?? 'Uncategorized';
    const categoryKey = category.toString().toLowerCase();
    const incidentStatus = (doc.status ?? '').toString().toUpperCase();
    const approvedAt = doc.approvedAt ? this.formatTimestamp(doc.approvedAt) : undefined;
    const respondingAt = doc.respondingAt ? this.formatTimestamp(doc.respondingAt) : undefined;
    const respondingBy = doc.respondingBy ?? undefined;
    const arrivedAt = doc.arrivedAt ? this.formatTimestamp(doc.arrivedAt) : undefined;
    const arrivedBy = doc.arrivedBy ?? undefined;
    const resolvedAt = doc.resolvedAt ? this.formatTimestamp(doc.resolvedAt) : undefined;
    const resolvedBy = doc.resolvedBy ?? undefined;
    const flaggedAt = doc.flaggedAt ? this.formatTimestamp(doc.flaggedAt) : undefined;
    const flaggedBy = doc.flaggedBy ?? undefined;
    const isFlagged = incidentStatus === 'FLAGGED';
    const imageSources = this.firebaseStorageService.getReportImageSources({
      mediaUrl: doc.mediaUrl,
      mediaPath: doc.mediaPath,
      mediaThumbUrl: doc.mediaThumbUrl,
      mediaThumbPath: doc.mediaThumbPath,
      mediaThumbWebpUrl: doc.mediaThumbWebpUrl,
      mediaThumbWebpPath: doc.mediaThumbWebpPath,
    });

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
      category,
      categoryKey,
      incidentFilterKey: this.toIncidentFilterKey(categoryKey),
      location: locationStr,
      date: dateStr,
      time: timeStr,
      reporter: doc.name ?? doc.reporter ?? 'Unknown reporter',
      description: doc.details ?? doc.description ?? 'No description provided.',
      image: imageSources.image,
      imageThumb: imageSources.imageThumb,
      imageThumbWebp: imageSources.imageThumbWebp,
      greenFlags: doc.greenFlags ?? 0,
      redFlags: doc.redFlags ?? 0,
      comments: doc.comments ?? 0,
      status: status,
      incidentStatus,
      sortTimestamp,
      approvedBy: doc.approvedBy ?? undefined,
      approvedAt,
      respondingAt,
      respondingBy,
      arrivedAt,
      arrivedBy,
      resolvedAt,
      resolvedBy,
      flaggedAt,
      flaggedBy,
      activityResponderDisplay: this.valueOrDash(
        respondingBy ?? arrivedBy ?? resolvedBy ?? flaggedBy,
      ),
      timeRespondingDisplay: this.valueOrDash(respondingAt),
      timeOnSceneDisplay: this.valueOrDash(arrivedAt),
      finalActivityLabelDisplay: isFlagged ? 'Time Flagged:' : 'Time Approved:',
      finalActivityTimeDisplay: isFlagged
        ? this.valueOrDash(flaggedAt)
        : this.valueOrDash(resolvedAt ?? approvedAt),
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
    this.showDateDropdown = false;
    this.showIncidentDropdown = false;
  }

  selectFilter(filter: FilterType) {
    this.currentFilter = filter;
    this.showFilterDropdown = false;
    this.recomputeFilteredReports(true);
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
    this.recomputeFilteredReports(true);
    this.cdr.markForCheck();
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
    this.recomputeFilteredReports(true);
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
      this.detachCommentListener(report.id);
      this.expandedReportId = null;
      this.loadingComments[report.id] = false;
      this.loadingMoreComments[report.id] = false;
      this.cdr.markForCheck();
      return;
    }

    if (this.expandedReportId) {
      this.detachCommentListener(this.expandedReportId);
    }

    this.expandedReportId = report.id;
    this.cdr.markForCheck();

    const hasCachedComments = Array.isArray(this.reportComments[report.id]);
    this.ensureCommentState(report.id, !hasCachedComments);
    if (hasCachedComments) {
      this.syncVisibleComments(report.id);
    }
    this.loadingComments[report.id] = !hasCachedComments;
    this.cdr.markForCheck();

    try {
      this.ngZone.runOutsideAngular(() => {
        const commentsRef = collection(db, 'reports', report.id, 'comments');
        const commentsQuery = query(
          commentsRef,
          orderBy('timestamp', 'desc'),
          limit(this.initialCommentsServerPageSize),
        );
        this.detachCommentListener(report.id);
        let isInitialSnapshot = true;
        const shouldResetVisibleWindow = !hasCachedComments;

        const unsubscribe = onSnapshot(
          commentsQuery,
          (snapshot) => {
            const currentLiveComments = isInitialSnapshot
              ? []
              : (this.liveReportComments[report.id] ?? []);
            const resetVisibleWindow = isInitialSnapshot && shouldResetVisibleWindow;
            const liveComments = this.applyCommentDocChanges(
              currentLiveComments,
              snapshot.docChanges(),
              report.id,
            );
            isInitialSnapshot = false;
            this.ngZone.run(() => {
              this.liveReportComments[report.id] = liveComments;
              const pagedComments = this.pagedReportComments[report.id] ?? [];
              this.reportComments[report.id] = this.mergeCommentLists(liveComments, pagedComments);
              this.touchCommentCache(report.id);
              if (snapshot.docs.length > 0) {
                this.commentPageCursors[report.id] = snapshot.docs[snapshot.docs.length - 1];
              }
              this.hasMoreServerComments[report.id] =
                snapshot.docs.length === this.initialCommentsServerPageSize;
              this.syncVisibleComments(report.id, resetVisibleWindow);
              this.loadingComments[report.id] = false;
              this.cdr.markForCheck();
            });
          },
          (error) => {
            console.error('Error in comments snapshot:', error);
            this.ngZone.run(() => {
              this.loadingComments[report.id] = false;
              this.reportComments[report.id] = this.reportComments[report.id] ?? [];
              this.hasMoreServerComments[report.id] = false;
              this.syncVisibleComments(report.id);
              this.cdr.markForCheck();
            });
          },
        );

        this.commentUnsubscribers[report.id] = unsubscribe;
      });
    } catch (err) {
      console.error('Error loading comments:', err);
      this.ngZone.run(() => {
        this.loadingComments[report.id] = false;
        this.reportComments[report.id] = this.reportComments[report.id] ?? [];
        this.hasMoreServerComments[report.id] = false;
        this.syncVisibleComments(report.id);
        this.cdr.markForCheck();
      });
    }
  }

  private applyCommentDocChanges(
    currentComments: Comment[],
    changes: any[],
    reportId: string,
  ): Comment[] {
    if (!changes || changes.length === 0) {
      return currentComments;
    }

    const nextComments = [...currentComments];

    for (const change of changes) {
      if (!change?.doc) continue;

      const mappedComment = this.mapComment(change.doc, reportId);

      switch (change.type) {
        case 'added':
          if (change.newIndex >= 0 && change.newIndex <= nextComments.length) {
            nextComments.splice(change.newIndex, 0, mappedComment);
          } else {
            nextComments.push(mappedComment);
          }
          break;

        case 'modified': {
          if (change.oldIndex >= 0 && change.oldIndex < nextComments.length) {
            nextComments.splice(change.oldIndex, 1);
          } else {
            const staleIndex = nextComments.findIndex(
              (comment) => comment.id === mappedComment.id,
            );
            if (staleIndex >= 0) {
              nextComments.splice(staleIndex, 1);
            }
          }

          if (change.newIndex >= 0 && change.newIndex <= nextComments.length) {
            nextComments.splice(change.newIndex, 0, mappedComment);
          } else {
            nextComments.push(mappedComment);
          }
          break;
        }

        case 'removed': {
          if (change.oldIndex >= 0 && change.oldIndex < nextComments.length) {
            nextComments.splice(change.oldIndex, 1);
          } else {
            const removedIndex = nextComments.findIndex(
              (comment) => comment.id === change.doc.id,
            );
            if (removedIndex >= 0) {
              nextComments.splice(removedIndex, 1);
            }
          }
          break;
        }

        default:
          break;
      }
    }

    return nextComments;
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
      displayTime: this.formatCommentTime(timestampDate),
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


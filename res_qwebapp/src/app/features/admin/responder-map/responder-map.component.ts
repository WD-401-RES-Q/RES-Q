import { AfterViewInit, Component, NgZone, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import {
  collection,
  doc,
  onSnapshot,
  serverTimestamp,
  setDoc,
  Unsubscribe,
  updateDoc,
} from 'firebase/firestore';
import { db } from '../../../core/config/firebase.config';

declare const L: any;

interface ResponderTrack {
  reportId: string;
  responderName?: string | null;
  responderStatus?: string | null;
  responderUnit?: string | null;
  responderId?: string | null;
  responderContactNumber?: string | null;
  incidentType?: string | null;
  reporterName?: string | null;
  reporterContactNumber?: string | null;
  barangay?: string | null;
  reportLocationLat: number;
  reportLocationLng: number;
  reporterLocationLat?: number | null;
  reporterLocationLng?: number | null;
  reporterLocationUpdatedAt?: Date | null;
  responderLocationLat?: number | null;
  responderLocationLng?: number | null;
  responderLocationUpdatedAt?: Date | null;
  reportStatus?: string | null;
  deployedAt?: Date | null;
  respondingAt?: Date | null;
  details?: string | null;
  mediaUrl?: string | null;
  mediaType?: string | null;
  reportedAt?: Date | null;
}

interface ResponderProfile {
  id: string;
  fullName: string;
  contactNumber?: string | null;
  role?: string | null;
  isLoggedIn: boolean;
  activityStatus: 'available' | 'busy' | 'offline';
  isAvailable: boolean;
  assignedReportId?: string | null;
  assignedStatus?: string | null;
}

type MapFocusTarget = 'auto' | 'report' | 'reporter' | 'responder';

@Component({
  selector: 'app-responder-map',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './responder-map.html',
  styleUrls: ['./responder-map.component.scss'],
})
export class ResponderMapComponent implements AfterViewInit, OnDestroy {
  reports: ResponderTrack[] = [];
  activeDeployments: ResponderTrack[] = [];
  pendingReports: ResponderTrack[] = [];
  responders: ResponderProfile[] = [];

  selectedId: string | null = null;
  selectedReportId: string | null = null;
  selectedResponderId: string | null = null;
  isDeploying = false;

  mapLoadError = '';
  isListening = false;
  isLoading = true;

  private map?: any;
  private responderLayer?: any;
  private reportLayer?: any;
  private reporterLayer?: any;
  private routeLayer?: any;
  private geofenceCircle?: any;

  private reportsUnsubscribe?: Unsubscribe;
  private respondersUnsubscribe?: Unsubscribe;
  private respondersRaw: ResponderProfile[] = [];

  private responderMarkerByReportId = new Map<string, any>();
  private reportMarkerByReportId = new Map<string, any>();
  private reporterMarkerByReportId = new Map<string, any>();
  private selectedRouteCasing?: any;
  private selectedRouteLine?: any;

  private resizeHandler?: () => void;
  private resizeObserver?: ResizeObserver;
  private routeRefreshTimer?: ReturnType<typeof setTimeout>;
  private reportsRetryTimer?: ReturnType<typeof setTimeout>;
  private respondersRetryTimer?: ReturnType<typeof setTimeout>;
  private routeRequestId = 0;

  private readonly angelesCenter = { lat: 15.145, lng: 120.5887 };
  private readonly angelesRadiusMeters = 6000;

  constructor(private ngZone: NgZone) {}

  ngAfterViewInit(): void {
    if (typeof L === 'undefined') {
      this.mapLoadError = 'Map library failed to load. Check your network connection.';
      return;
    }

    this.map = L.map('responder-map', {
      zoomControl: true,
      attributionControl: true,
    }).setView([this.angelesCenter.lat, this.angelesCenter.lng], 13);

    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; OpenStreetMap contributors',
    }).addTo(this.map);

    this.geofenceCircle = L.circle([this.angelesCenter.lat, this.angelesCenter.lng], {
      radius: this.angelesRadiusMeters,
      color: '#00A458',
      weight: 2,
      fillColor: '#00A458',
      fillOpacity: 0.07,
    }).addTo(this.map);

    this.reportLayer = L.layerGroup().addTo(this.map);
    this.reporterLayer = L.layerGroup().addTo(this.map);
    this.responderLayer = L.layerGroup().addTo(this.map);
    this.routeLayer = L.layerGroup().addTo(this.map);
    this.ensureMapRenders();
    this.startRealtimeTracking();
    this.startResponderRoster();
  }

  ngOnDestroy(): void {
    if (this.reportsUnsubscribe) {
      this.reportsUnsubscribe();
    }
    if (this.respondersUnsubscribe) {
      this.respondersUnsubscribe();
    }
    if (this.routeRefreshTimer) {
      clearTimeout(this.routeRefreshTimer);
    }
    if (this.reportsRetryTimer) {
      clearTimeout(this.reportsRetryTimer);
    }
    if (this.respondersRetryTimer) {
      clearTimeout(this.respondersRetryTimer);
    }
    this.clearSelectedRoute();
    if (this.map) {
      this.map.remove();
    }
    this.responderMarkerByReportId.clear();
    this.reportMarkerByReportId.clear();
    this.reporterMarkerByReportId.clear();
    if (this.resizeHandler) {
      window.removeEventListener('resize', this.resizeHandler);
    }
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
    }
  }

  trackById(_: number, track: ResponderTrack): string {
    return track.reportId;
  }

  trackResponderById(_: number, responder: ResponderProfile): string {
    return responder.id;
  }

  focusResponder(reportId: string, target: MapFocusTarget = 'auto'): void {
    const track = this.reports.find((t) => t.reportId === reportId);
    if (!track) return;

    this.selectedId = reportId;
    this.selectedReportId = reportId;

    this.highlightSelectedMarker();
    this.scheduleRouteRefresh();

    if (!this.map) return;

    const canUseResponderFocus =
      this.hasResponderAssignment(track) &&
      typeof track.responderLocationLat === 'number' &&
      typeof track.responderLocationLng === 'number';

    const canUseReporterFocus =
      typeof track.reporterLocationLat === 'number' &&
      typeof track.reporterLocationLng === 'number';

    let focusLat = track.reportLocationLat;
    let focusLng = track.reportLocationLng;

    if (target === 'reporter' && canUseReporterFocus) {
      focusLat = track.reporterLocationLat!;
      focusLng = track.reporterLocationLng!;
    } else if (target === 'responder' && canUseResponderFocus) {
      focusLat = track.responderLocationLat!;
      focusLng = track.responderLocationLng!;
    } else if (target === 'auto' && canUseResponderFocus) {
      focusLat = track.responderLocationLat!;
      focusLng = track.responderLocationLng!;
    }

    this.map.setView([focusLat, focusLng], 15, {
      animate: true,
    });
  }

  selectReportForDispatch(reportId: string): void {
    this.selectedReportId = reportId;
    const track = this.reports.find((entry) => entry.reportId === reportId);
    const hasReporterLocation =
      !!track &&
      typeof track.reporterLocationLat === 'number' &&
      typeof track.reporterLocationLng === 'number';
    const focusTarget: MapFocusTarget = hasReporterLocation ? 'reporter' : 'report';
    this.focusResponder(reportId, focusTarget);
    this.openReportDetailsPopup(reportId, focusTarget);
  }

  selectResponder(responderId: string): void {
    this.selectedResponderId = responderId;
  }

  get selectedTrack(): ResponderTrack | null {
    if (!this.selectedId) return null;
    return this.activeDeployments.find((t) => t.reportId === this.selectedId) ?? null;
  }

  get selectedResponder(): ResponderProfile | null {
    if (!this.selectedResponderId) return null;
    return this.responders.find((item) => item.id === this.selectedResponderId) ?? null;
  }

  get canDeploySelection(): boolean {
    if (!this.selectedReportId || !this.selectedResponderId) return false;
    const report = this.pendingReports.find((entry) => entry.reportId === this.selectedReportId);
    const responder = this.responders.find((entry) => entry.id === this.selectedResponderId);
    return Boolean(report && responder && responder.isAvailable);
  }

  get availableRespondersCount(): number {
    return this.responders.filter((entry) => entry.isAvailable).length;
  }

  getResponderActivityLabel(responder: ResponderProfile): string {
    if (responder.activityStatus === 'offline') {
      return 'OFFLINE';
    }
    return responder.activityStatus.toUpperCase();
  }

  formatTimestamp(value?: Date | null): string {
    if (!value) return 'Unknown';
    return value.toLocaleString();
  }

  private escapeHtml(value: string): string {
    return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  }

  private formatPopupTimestamp(value?: Date | null): string {
    if (!value) return 'Unknown';
    return value.toLocaleString();
  }

  private buildReportPopup(track: ResponderTrack, locationLabel: string): string {
    const incidentType = this.escapeHtml(track.incidentType ?? 'Incident');
    const reporter = this.escapeHtml(track.reporterName ?? 'Unknown reporter');
    const barangay = this.escapeHtml(track.barangay ?? 'Angeles City');
    const status = this.escapeHtml(this.getStatusLabel(track.responderStatus || track.reportStatus));
    const detailsRaw = (track.details ?? '').toString().trim();
    const details =
      detailsRaw.length > 260
        ? `${this.escapeHtml(detailsRaw.slice(0, 260))}...`
        : this.escapeHtml(detailsRaw);

    const mediaType = (track.mediaType ?? '').toString().toLowerCase();
    const mediaUrlRaw = (track.mediaUrl ?? '').toString().trim();
    const safeMediaUrl = mediaUrlRaw.replaceAll('"', '&quot;');
    const hasMedia = mediaUrlRaw.length > 0;

    let mediaHtml = '<div style="margin-top:8px;color:#6b7280;font-size:12px;">No media attached.</div>';
    if (hasMedia && mediaType === 'photo') {
      mediaHtml =
        `<div style="margin-top:8px;">` +
        `<img src="${safeMediaUrl}" alt="Report photo" style="display:block;width:100%;max-width:260px;max-height:180px;object-fit:cover;border-radius:10px;border:1px solid #e5e7eb;" />` +
        `<a href="${safeMediaUrl}" target="_blank" rel="noopener noreferrer" style="display:inline-block;margin-top:6px;color:#0B5FFF;font-size:12px;text-decoration:none;">Open image</a>` +
        `</div>`;
    } else if (hasMedia) {
      mediaHtml =
        `<div style="margin-top:8px;">` +
        `<a href="${safeMediaUrl}" target="_blank" rel="noopener noreferrer" style="color:#0B5FFF;font-size:12px;text-decoration:none;">Open attached media</a>` +
        `</div>`;
    }

    return (
      `<div style="min-width:220px;max-width:280px;font-family:Roboto,Arial,sans-serif;">` +
      `<div style="font-weight:700;color:#111827;font-size:13px;">${this.escapeHtml(locationLabel)}</div>` +
      `<div style="margin-top:4px;color:#1f2937;font-size:13px;">${incidentType}</div>` +
      `<div style="margin-top:2px;color:#6b7280;font-size:12px;">Report ID: ${this.escapeHtml(track.reportId)}</div>` +
      `<div style="margin-top:2px;color:#6b7280;font-size:12px;">Reporter: ${reporter}</div>` +
      `<div style="margin-top:2px;color:#6b7280;font-size:12px;">Barangay: ${barangay}</div>` +
      `<div style="margin-top:2px;color:#6b7280;font-size:12px;">Status: ${status}</div>` +
      `<div style="margin-top:2px;color:#6b7280;font-size:12px;">Reported: ${this.escapeHtml(this.formatPopupTimestamp(track.reportedAt))}</div>` +
      (details ? `<div style="margin-top:6px;color:#374151;font-size:12px;">${details}</div>` : '') +
      mediaHtml +
      `</div>`
    );
  }

  formatCoord(value?: number | null): string {
    if (value === undefined || value === null || Number.isNaN(value)) {
      return '-';
    }
    return value.toFixed(5);
  }

  getStatusLabel(value?: string | null): string {
    const raw = (value ?? '').toString().trim();
    return raw ? raw.toUpperCase() : 'ACTIVE';
  }

  getStatusColor(value?: string | null): string {
    const status = this.normalizeStatus(value);
    if (status === 'pending') return '#2563eb';
    if (status === 'responding') return '#ffc806';
    if (status === 'on scene' || status === 'on_scene' || status === 'onscene') return '#ac1b22';
    if (status === 'resolved' || status === 'approved') return '#00a458';
    if (status === 'flagged') return '#ac1b22';
    return '#6b7280';
  }

  getStatusTextColor(value?: string | null): string {
    const status = this.normalizeStatus(value);
    if (status === 'responding') return '#1f2937';
    return '#ffffff';
  }

  canDial(value?: string | null): boolean {
    return this.normalizePhone(value).length >= 7;
  }

  openDialer(value?: string | null): void {
    const phone = this.normalizePhone(value);
    if (!phone) return;
    window.location.href = `tel:${phone}`;
  }

  async deploySelectedResponder(): Promise<void> {
    if (!this.canDeploySelection || this.isDeploying || !this.selectedReportId || !this.selectedResponder) {
      return;
    }

    const selectedReport = this.pendingReports.find((entry) => entry.reportId === this.selectedReportId);
    if (!selectedReport) {
      this.mapLoadError = 'Selected report is no longer pending deployment.';
      return;
    }

    if (!this.selectedResponder.isAvailable) {
      this.mapLoadError = 'Selected responder is no longer available.';
      return;
    }

    this.isDeploying = true;
    this.mapLoadError = '';
    try {
      const payload: Record<string, unknown> = {
        responderId: this.selectedResponder.id,
        responderName: this.selectedResponder.fullName,
        responderStatus: 'PENDING',
        status: 'PENDING',
        deployedAt: serverTimestamp(),
        respondingAt: null,
        responderAssignedAt: serverTimestamp(),
        deployedBy: this.getCurrentAdminName(),
        responderStatusUpdatedAt: serverTimestamp(),
        responderStatusUpdatedBy: this.getCurrentAdminName(),
        updatedAt: serverTimestamp(),
      };

      if (this.selectedResponder.contactNumber) {
        payload['responderContactNumber'] = this.selectedResponder.contactNumber;
      }

      await updateDoc(doc(db, 'reports', this.selectedReportId), payload);
      await setDoc(
        doc(db, 'semi_admins', this.selectedResponder.id),
        {
          isLoggedIn: true,
          status: 'busy',
          isAvailable: false,
          lastSeenAt: serverTimestamp(),
        },
        { merge: true },
      );
      this.selectedId = this.selectedReportId;
      this.focusResponder(this.selectedReportId);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'unknown error';
      this.mapLoadError = `Failed to deploy responder: ${message}`;
    } finally {
      this.isDeploying = false;
    }
  }

  refreshTracking(): void {
    this.updateMarkers();
    this.ensureMapRenders();
    this.scheduleRouteRefresh();
    if (this.selectedId) {
      this.focusResponder(this.selectedId);
      return;
    }
    if (this.reports.length > 0) {
      this.fitToResponders();
    }
  }

  fitToResponders(): void {
    if (!this.map || this.reports.length === 0) return;
    const points: Array<[number, number]> = [];
    this.reports.forEach((track) => {
      points.push([track.reportLocationLat, track.reportLocationLng]);
      if (
        typeof track.responderLocationLat === 'number' &&
        typeof track.responderLocationLng === 'number'
      ) {
        points.push([track.responderLocationLat, track.responderLocationLng]);
      }
      if (
        typeof track.reporterLocationLat === 'number' &&
        typeof track.reporterLocationLng === 'number'
      ) {
        points.push([track.reporterLocationLat, track.reporterLocationLng]);
      }
    });
    if (points.length === 0) return;
    const bounds = L.latLngBounds(points);
    this.map.fitBounds(bounds.pad(0.2));
  }

  hardRefresh(): void {
    const url = new URL(window.location.href);
    url.searchParams.set('refresh', Date.now().toString());
    window.location.replace(url.toString());
  }

  private toLatLng(raw: any): { lat: number; lng: number } | null {
    if (!raw) return null;

    if (typeof raw.latitude === 'number' && typeof raw.longitude === 'number') {
      return { lat: raw.latitude, lng: raw.longitude };
    }

    if (typeof raw.lat === 'number' && typeof raw.lng === 'number') {
      return { lat: raw.lat, lng: raw.lng };
    }

    return null;
  }

  private toNumber(raw: unknown): number | null {
    if (typeof raw === 'number' && Number.isFinite(raw)) {
      return raw;
    }
    if (typeof raw === 'string' && raw.trim().length > 0) {
      const parsed = Number(raw);
      if (Number.isFinite(parsed)) {
        return parsed;
      }
    }
    return null;
  }

  private extractPointFromFields(latRaw: unknown, lngRaw: unknown): { lat: number; lng: number } | null {
    const lat = this.toNumber(latRaw);
    const lng = this.toNumber(lngRaw);
    if (lat === null || lng === null) {
      return null;
    }
    return { lat, lng };
  }

  private extractReportPoint(data: any, reporterPoint: { lat: number; lng: number } | null): { lat: number; lng: number } | null {
    return (
      this.toLatLng(data?.incidentLocation) ??
      this.toLatLng(data?.location) ??
      this.extractPointFromFields(data?.incidentLocationLat, data?.incidentLocationLng) ??
      this.extractPointFromFields(data?.locationLat, data?.locationLng) ??
      this.extractPointFromFields(data?.latitude, data?.longitude) ??
      reporterPoint
    );
  }

  private toDate(value: any): Date | null {
    if (value && typeof value.toDate === 'function') {
      return value.toDate();
    }
    if (value instanceof Date) {
      return value;
    }
    return null;
  }

  private normalizeStatus(value?: string | null): string {
    return (value ?? '').toString().trim().toLowerCase();
  }

  private normalizePhone(value?: string | null): string {
    return (value ?? '').toString().replace(/\D/g, '');
  }

  private isClosedStatus(status: string): boolean {
    return (
      status === 'resolved' ||
      status === 'incident resolved' ||
      status === 'flagged' ||
      status === 'unverified'
    );
  }

  private hasResponderAssignment(track: ResponderTrack): boolean {
    const responderName = (track.responderName ?? '').toString().trim().toLowerCase();
    const hasNamedResponder =
      responderName.length > 0 &&
      responderName !== 'unknown' &&
      responderName !== 'responder';

    const hasIdentity =
      this.normalizePhone(track.responderId).length > 0 ||
      this.normalizePhone(track.responderContactNumber).length > 0 ||
      hasNamedResponder;

    if (!hasIdentity) return false;

    const status = this.normalizeStatus(track.responderStatus ?? track.reportStatus ?? null);
    const hasDispatchStatus =
      status === 'responding' ||
      status === 'on scene' ||
      status === 'onscene' ||
      status === 'on_scene' ||
      status === 'deployed' ||
      status === 'dispatched';

    const hasDispatchMeta = Boolean(track.deployedAt || track.respondingAt);
    return hasDispatchStatus || hasDispatchMeta;
  }

  private isTrackAssignedToResponder(track: ResponderTrack, responder: ResponderProfile): boolean {
    if (!this.hasResponderAssignment(track)) return false;

    if (track.responderId && track.responderId === responder.id) {
      return true;
    }

    const responderPhones = new Set<string>();
    const responderContact = this.normalizePhone(responder.contactNumber);
    const responderIdDigits = this.normalizePhone(responder.id);
    if (responderContact) responderPhones.add(responderContact);
    if (responderIdDigits) responderPhones.add(responderIdDigits);

    const trackPhones = new Set<string>();
    const trackContact = this.normalizePhone(track.responderContactNumber);
    const trackIdDigits = this.normalizePhone(track.responderId);
    if (trackContact) trackPhones.add(trackContact);
    if (trackIdDigits) trackPhones.add(trackIdDigits);

    for (const phone of responderPhones) {
      if (trackPhones.has(phone)) {
        return true;
      }
    }

    const responderName = responder.fullName.trim().toLowerCase();
    const trackName = (track.responderName ?? '').toString().trim().toLowerCase();
    return Boolean(responderName && trackName && responderName === trackName);
  }

  private getCurrentAdminName(): string {
    try {
      const raw = localStorage.getItem('currentAdmin');
      if (!raw) return 'admin';
      const parsed = JSON.parse(raw) as { username?: string; id?: string };
      return (parsed.username ?? parsed.id ?? 'admin').toString();
    } catch {
      return 'admin';
    }
  }

  private startRealtimeTracking(): void {
    if (this.reportsUnsubscribe) {
      this.reportsUnsubscribe();
      this.reportsUnsubscribe = undefined;
    }
    if (this.reportsRetryTimer) {
      clearTimeout(this.reportsRetryTimer);
      this.reportsRetryTimer = undefined;
    }
    const reportsRef = collection(db, 'reports');
    this.reportsUnsubscribe = onSnapshot(
      reportsRef,
      { includeMetadataChanges: true },
      (snapshot) => {
        const nextReports: ResponderTrack[] = [];

        snapshot.docs.forEach((snapshotDoc) => {
          const data = snapshotDoc.data() as any;

          const statusLower = this.normalizeStatus(data?.status);
          const responderStatusLower = this.normalizeStatus(data?.responderStatus);
          if (this.isClosedStatus(statusLower) || this.isClosedStatus(responderStatusLower)) {
            return;
          }

          let reporterPoint =
            this.toLatLng(data?.reporterLocation) ??
            this.extractPointFromFields(
              data?.reporterLocationLat,
              data?.reporterLocationLng,
            );

          const reportPoint = this.extractReportPoint(data, reporterPoint);
          if (!reportPoint) return;

          const responderPoint =
            this.toLatLng(data?.responderLocation) ??
            this.extractPointFromFields(
              data?.responderLocationLat,
              data?.responderLocationLng,
            );

          const source = (data?.locationSource ?? '').toString().toLowerCase();
          if (!reporterPoint && source === 'current') {
            reporterPoint = reportPoint;
          }

          nextReports.push({
            reportId: snapshotDoc.id,
            responderName: data?.responderName ?? data?.responder ?? null,
            responderStatus: data?.responderStatus ?? null,
            responderUnit: data?.responderUnit ?? null,
            responderId: data?.responderId ?? null,
            responderContactNumber: data?.responderContactNumber ?? null,
            incidentType: data?.incidentType ?? null,
            reporterName: data?.name ?? null,
            reporterContactNumber: data?.contactNumber ?? null,
            barangay: data?.barangay ?? null,
            reportLocationLat: reportPoint.lat,
            reportLocationLng: reportPoint.lng,
            reporterLocationLat: reporterPoint?.lat ?? null,
            reporterLocationLng: reporterPoint?.lng ?? null,
            reporterLocationUpdatedAt: this.toDate(data?.reporterLocationUpdatedAt),
            responderLocationLat: responderPoint?.lat ?? null,
            responderLocationLng: responderPoint?.lng ?? null,
            responderLocationUpdatedAt: this.toDate(data?.responderLocationUpdatedAt),
            reportStatus: data?.status ?? null,
            deployedAt: this.toDate(data?.deployedAt) ?? this.toDate(data?.responderAssignedAt),
            respondingAt: this.toDate(data?.respondingAt),
            details: data?.details ?? data?.description ?? null,
            mediaUrl: data?.mediaUrl ?? null,
            mediaType: data?.mediaType ?? null,
            reportedAt: this.toDate(data?.reportedAt),
          });
        });

        this.ngZone.run(() => {
          this.reports = nextReports;
          this.syncDerivedState();
          this.isLoading = false;
          this.isListening = !snapshot.metadata.fromCache;
          this.updateMarkers();
          this.scheduleRouteRefresh();
        });
      },
      () => {
        this.ngZone.run(() => {
          this.mapLoadError = 'Unable to subscribe to responder updates.';
          this.isListening = false;
          this.isLoading = false;
        });
        this.reportsRetryTimer = setTimeout(() => this.startRealtimeTracking(), 2000);
      },
    );
  }

  private startResponderRoster(): void {
    if (this.respondersUnsubscribe) {
      this.respondersUnsubscribe();
      this.respondersUnsubscribe = undefined;
    }
    if (this.respondersRetryTimer) {
      clearTimeout(this.respondersRetryTimer);
      this.respondersRetryTimer = undefined;
    }
    const respondersRef = collection(db, 'semi_admins');
    this.respondersUnsubscribe = onSnapshot(
      respondersRef,
      { includeMetadataChanges: true },
      (snapshot) => {
        const nextResponders: ResponderProfile[] = snapshot.docs.map((snapshotDoc) => {
          const data = snapshotDoc.data() as any;
          const statusRaw = (data?.status ?? '')
            .toString()
            .trim()
            .toLowerCase();

          const isLoggedIn =
            typeof data?.isLoggedIn === 'boolean'
              ? data.isLoggedIn
              : false;

          const activityStatus: 'available' | 'busy' | 'offline' =
            !isLoggedIn ? 'offline' : statusRaw === 'busy' ? 'busy' : 'available';

          return {
            id: snapshotDoc.id,
            fullName:
              (data?.fullName ?? data?.username ?? data?.name ?? snapshotDoc.id).toString(),
            contactNumber:
              typeof data?.contactNumber === 'string' ? data.contactNumber : null,
            role: typeof data?.role === 'string' ? data.role : null,
            isLoggedIn,
            activityStatus,
            isAvailable: isLoggedIn && activityStatus === 'available',
          };
        });

        this.ngZone.run(() => {
          this.respondersRaw = nextResponders;
          this.isListening = !snapshot.metadata.fromCache;
          this.syncDerivedState();
        });
      },
      () => {
        this.ngZone.run(() => {
          this.mapLoadError = 'Unable to load responder roster.';
          this.isListening = false;
        });
        this.respondersRetryTimer = setTimeout(() => this.startResponderRoster(), 2000);
      },
    );
  }

  private syncDerivedState(): void {
    this.activeDeployments = this.reports.filter((track) => this.hasResponderAssignment(track));
    this.pendingReports = this.reports.filter((track) => !this.hasResponderAssignment(track));

    this.activeDeployments.sort((a, b) => {
      const aTime = (a.respondingAt ?? a.deployedAt)?.getTime() ?? 0;
      const bTime = (b.respondingAt ?? b.deployedAt)?.getTime() ?? 0;
      return bTime - aTime;
    });

    this.pendingReports.sort((a, b) => a.reportId.localeCompare(b.reportId));

    this.recomputeResponderAvailability();

    if (this.selectedId && !this.reports.some((track) => track.reportId === this.selectedId)) {
      this.selectedId = null;
    }
    if (!this.selectedId) {
      this.selectedId =
        this.activeDeployments[0]?.reportId ?? this.pendingReports[0]?.reportId ?? null;
    }

    if (
      this.selectedReportId &&
      !this.reports.some((track) => track.reportId === this.selectedReportId)
    ) {
      this.selectedReportId = null;
    }
    if (!this.selectedReportId) {
      this.selectedReportId = this.pendingReports[0]?.reportId ?? this.selectedId;
    }

    if (
      this.selectedResponderId &&
      !this.responders.some((responder) => responder.id === this.selectedResponderId)
    ) {
      this.selectedResponderId = null;
    }
    if (!this.selectedResponderId) {
      this.selectedResponderId =
        this.responders.find((responder) => responder.isAvailable)?.id ?? null;
    }
  }

  private recomputeResponderAvailability(): void {
    this.responders = this.respondersRaw
      .map((responder) => {
        const assignment = this.activeDeployments.find((track) =>
          this.isTrackAssignedToResponder(track, responder),
        );
        const activityStatus: 'available' | 'busy' | 'offline' = !responder.isLoggedIn
          ? 'offline'
          : assignment
            ? 'busy'
            : 'available';

        return {
          ...responder,
          activityStatus,
          isAvailable: activityStatus === 'available',
          assignedReportId: assignment?.reportId ?? null,
          assignedStatus: assignment?.responderStatus ?? assignment?.reportStatus ?? null,
        };
      })
      .sort((a, b) => {
        const rank: Record<'available' | 'busy' | 'offline', number> = {
          available: 0,
          busy: 1,
          offline: 2,
        };
        if (rank[a.activityStatus] !== rank[b.activityStatus]) {
          return rank[a.activityStatus] - rank[b.activityStatus];
        }
        return a.fullName.localeCompare(b.fullName);
      });
  }

  private ensureMapRenders(): void {
    if (!this.map) return;
    const invalidate = () => this.map?.invalidateSize();
    setTimeout(invalidate, 0);
    setTimeout(invalidate, 200);

    this.resizeHandler = () => invalidate();
    window.addEventListener('resize', this.resizeHandler);

    const container = document.getElementById('responder-map');
    if (container && 'ResizeObserver' in window) {
      this.resizeObserver = new ResizeObserver(() => invalidate());
      this.resizeObserver.observe(container);
    }
  }

  private updateMarkers(): void {
    if (!this.map || !this.responderLayer || !this.reportLayer || !this.reporterLayer) return;
    const nextIds = new Set(this.reports.map((track) => track.reportId));

    for (const [reportId, marker] of this.responderMarkerByReportId.entries()) {
      if (!nextIds.has(reportId)) {
        this.responderLayer.removeLayer(marker);
        this.responderMarkerByReportId.delete(reportId);
      }
    }

    for (const [reportId, marker] of this.reportMarkerByReportId.entries()) {
      if (!nextIds.has(reportId)) {
        this.reportLayer.removeLayer(marker);
        this.reportMarkerByReportId.delete(reportId);
      }
    }

    for (const [reportId, marker] of this.reporterMarkerByReportId.entries()) {
      if (!nextIds.has(reportId)) {
        this.reporterLayer.removeLayer(marker);
        this.reporterMarkerByReportId.delete(reportId);
      }
    }

    for (const track of this.reports) {
      const reportPopupContent = this.buildReportPopup(track, 'Report location');
      const reporterPopupContent = this.buildReportPopup(track, 'Reporter location');

      const reportExisting = this.reportMarkerByReportId.get(track.reportId);
      if (reportExisting) {
        reportExisting.setLatLng([track.reportLocationLat, track.reportLocationLng]);
        reportExisting.setPopupContent(reportPopupContent);
      } else {
        const reportMarker = L.circleMarker([track.reportLocationLat, track.reportLocationLng], {
          radius: 7,
          color: '#AC1B22',
          fillColor: '#AC1B22',
          fillOpacity: 0.9,
          weight: 2,
        });
        reportMarker.on('click', () => {
          this.ngZone.run(() => this.focusResponder(track.reportId, 'report'));
          reportMarker.openPopup();
        });
        reportMarker.bindPopup(reportPopupContent, { maxWidth: 320, closeButton: true });
        reportMarker.bindTooltip('Report location', {
          direction: 'top',
          offset: [0, -8],
        });
        reportMarker.addTo(this.reportLayer);
        this.reportMarkerByReportId.set(track.reportId, reportMarker);
      }

      if (
        typeof track.reporterLocationLat === 'number' &&
        typeof track.reporterLocationLng === 'number'
      ) {
        const reporterExisting = this.reporterMarkerByReportId.get(track.reportId);
        if (reporterExisting) {
          reporterExisting.setLatLng([track.reporterLocationLat, track.reporterLocationLng]);
          reporterExisting.setPopupContent(reporterPopupContent);
        } else {
          const reporterMarker = L.circleMarker(
            [track.reporterLocationLat, track.reporterLocationLng],
            {
              radius: 6.5,
              color: '#F59E0B',
              fillColor: '#F59E0B',
              fillOpacity: 0.9,
              weight: 2,
            },
          );
          reporterMarker.on('click', () => {
            this.ngZone.run(() => this.focusResponder(track.reportId, 'reporter'));
            reporterMarker.openPopup();
          });
          reporterMarker.bindPopup(reporterPopupContent, { maxWidth: 320, closeButton: true });
          reporterMarker.bindTooltip('Reporter location', {
            direction: 'top',
            offset: [0, -8],
          });
          reporterMarker.addTo(this.reporterLayer);
          this.reporterMarkerByReportId.set(track.reportId, reporterMarker);
        }
      } else {
        const existingReporter = this.reporterMarkerByReportId.get(track.reportId);
        if (existingReporter) {
          this.reporterLayer.removeLayer(existingReporter);
          this.reporterMarkerByReportId.delete(track.reportId);
        }
      }

      if (
        this.hasResponderAssignment(track) &&
        typeof track.responderLocationLat === 'number' &&
        typeof track.responderLocationLng === 'number'
      ) {
        const responderExisting = this.responderMarkerByReportId.get(track.reportId);
        if (responderExisting) {
          responderExisting.setLatLng([track.responderLocationLat, track.responderLocationLng]);
        } else {
          const responderMarker = L.circleMarker(
            [track.responderLocationLat, track.responderLocationLng],
            {
              radius: 8,
              color: '#0B5FFF',
              fillColor: '#0B5FFF',
              fillOpacity: 0.9,
              weight: 2,
            },
          );

          responderMarker.on('click', () => {
            this.ngZone.run(() => this.focusResponder(track.reportId, 'responder'));
          });

          const responderLabel =
            track.responderName ?? track.responderContactNumber ?? track.responderId ?? 'Responder';
          responderMarker.bindTooltip(
            `${responderLabel} - ${track.responderStatus ?? 'Active'}`,
            {
              direction: 'top',
              offset: [0, -8],
            },
          );

          responderMarker.addTo(this.responderLayer);
          this.responderMarkerByReportId.set(track.reportId, responderMarker);
        }
      } else {
        const existingResponder = this.responderMarkerByReportId.get(track.reportId);
        if (existingResponder) {
          this.responderLayer.removeLayer(existingResponder);
          this.responderMarkerByReportId.delete(track.reportId);
        }
      }
    }

    this.highlightSelectedMarker();
  }

  private highlightSelectedMarker(): void {
    for (const [reportId, marker] of this.reportMarkerByReportId.entries()) {
      const isSelected = reportId === this.selectedId;
      marker.setStyle({
        radius: isSelected ? 9 : 7,
        color: isSelected ? '#7F1D1D' : '#AC1B22',
        fillColor: isSelected ? '#7F1D1D' : '#AC1B22',
        fillOpacity: isSelected ? 1 : 0.9,
        weight: isSelected ? 3 : 2,
      });
    }

    for (const [reportId, marker] of this.reporterMarkerByReportId.entries()) {
      const isSelected = reportId === this.selectedId;
      marker.setStyle({
        radius: isSelected ? 8.5 : 6.5,
        color: isSelected ? '#D97706' : '#F59E0B',
        fillColor: isSelected ? '#D97706' : '#F59E0B',
        fillOpacity: isSelected ? 1 : 0.9,
        weight: isSelected ? 3 : 2,
      });
    }

    for (const [reportId, marker] of this.responderMarkerByReportId.entries()) {
      const isSelected = reportId === this.selectedId;
      marker.setStyle({
        radius: isSelected ? 11 : 8,
        color: isSelected ? '#00A458' : '#0B5FFF',
        fillColor: isSelected ? '#00A458' : '#0B5FFF',
        fillOpacity: isSelected ? 1 : 0.9,
        weight: isSelected ? 3 : 2,
      });
    }
  }

  private scheduleRouteRefresh(): void {
    if (this.routeRefreshTimer) {
      clearTimeout(this.routeRefreshTimer);
    }
    this.routeRefreshTimer = setTimeout(() => {
      void this.updateSelectedRoute();
    }, 250);
  }

  private openReportDetailsPopup(reportId: string, focusTarget: MapFocusTarget): void {
    const openPopup = () => {
      const reporterMarker = this.reporterMarkerByReportId.get(reportId);
      const reportMarker = this.reportMarkerByReportId.get(reportId);

      if (focusTarget === 'reporter' && reporterMarker && typeof reporterMarker.openPopup === 'function') {
        reporterMarker.openPopup();
        return;
      }

      if (reportMarker && typeof reportMarker.openPopup === 'function') {
        reportMarker.openPopup();
        return;
      }

      if (reporterMarker && typeof reporterMarker.openPopup === 'function') {
        reporterMarker.openPopup();
      }
    };

    // Delay a tick so map pan/zoom completes before opening popup.
    setTimeout(openPopup, 120);
  }

  private clearSelectedRoute(): void {
    this.routeRequestId += 1;

    if (this.routeLayer && this.selectedRouteCasing) {
      this.routeLayer.removeLayer(this.selectedRouteCasing);
      this.selectedRouteCasing = undefined;
    }
    if (this.routeLayer && this.selectedRouteLine) {
      this.routeLayer.removeLayer(this.selectedRouteLine);
      this.selectedRouteLine = undefined;
    }
  }

  private async updateSelectedRoute(): Promise<void> {
    if (!this.routeLayer) return;

    const selected = this.selectedTrack;
    if (
      !selected ||
      typeof selected.responderLocationLat !== 'number' ||
      typeof selected.responderLocationLng !== 'number'
    ) {
      this.clearSelectedRoute();
      return;
    }

    const origin = {
      lat: selected.responderLocationLat,
      lng: selected.responderLocationLng,
    };
    const destination = {
      lat: selected.reportLocationLat,
      lng: selected.reportLocationLng,
    };

    const requestId = ++this.routeRequestId;
    const points = await this.fetchRoutePolyline(origin, destination);

    if (requestId !== this.routeRequestId || !this.routeLayer) return;

    this.clearSelectedRoute();

    this.selectedRouteCasing = L.polyline(points, {
      color: '#ffffff',
      weight: 8,
      opacity: 0.9,
      lineCap: 'round',
      lineJoin: 'round',
      dashArray: '12 8',
    }).addTo(this.routeLayer);

    this.selectedRouteLine = L.polyline(points, {
      color: '#0B5FFF',
      weight: 4.5,
      opacity: 0.95,
      lineCap: 'round',
      lineJoin: 'round',
      dashArray: '12 8',
    }).addTo(this.routeLayer);
  }

  private async fetchRoutePolyline(
    origin: { lat: number; lng: number },
    destination: { lat: number; lng: number },
  ): Promise<Array<[number, number]>> {
    const fallback: Array<[number, number]> = [
      [origin.lat, origin.lng],
      [destination.lat, destination.lng],
    ];

    try {
      const url =
        'https://router.project-osrm.org/route/v1/driving/' +
        `${origin.lng},${origin.lat};${destination.lng},${destination.lat}` +
        '?overview=full&geometries=geojson&alternatives=false';

      const response = await fetch(url);
      if (!response.ok) {
        return fallback;
      }

      const payload = (await response.json()) as {
        routes?: Array<{ geometry?: { coordinates?: number[][] } }>;
      };
      const coordinates = payload.routes?.[0]?.geometry?.coordinates;
      if (!coordinates || coordinates.length < 2) {
        return fallback;
      }

      const points = coordinates
        .filter(
          (coord) =>
            Array.isArray(coord) &&
            coord.length >= 2 &&
            typeof coord[0] === 'number' &&
            typeof coord[1] === 'number',
        )
        .map((coord) => [coord[1], coord[0]] as [number, number]);

      return points.length >= 2 ? points : fallback;
    } catch {
      return fallback;
    }
  }
}

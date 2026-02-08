import { AfterViewInit, Component, NgZone, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { collection, onSnapshot, Unsubscribe } from 'firebase/firestore';
import { db } from '../../../core/config/firebase.config';

declare const L: any;

interface ResponderTrack {
  reportId: string;
  responderName?: string;
  responderStatus?: string;
  responderUnit?: string;
  responderId?: string;
  incidentType?: string;
  reporterName?: string;
  barangay?: string;
  reportLocationLat: number;
  reportLocationLng: number;
  reporterLocationLat?: number | null;
  reporterLocationLng?: number | null;
  reporterLocationUpdatedAt?: Date | null;
  responderLocationLat: number;
  responderLocationLng: number;
  responderLocationUpdatedAt?: Date | null;
  reportStatus?: string;
}

@Component({
  selector: 'app-responder-map',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './responder-map.html',
  styleUrls: ['./responder-map.component.scss'],
})
export class ResponderMapComponent implements AfterViewInit, OnDestroy {
  tracks: ResponderTrack[] = [];
  selectedId: string | null = null;
  mapLoadError = '';
  isListening = false;
  isLoading = true;

  private map?: any;
  private responderLayer?: any;
  private reportLayer?: any;
  private reporterLayer?: any;
  private geofenceCircle?: any;
  private unsubscribe?: Unsubscribe;
  private responderMarkerByReportId = new Map<string, any>();
  private reportMarkerByReportId = new Map<string, any>();
  private reporterMarkerByReportId = new Map<string, any>();
  private resizeHandler?: () => void;
  private resizeObserver?: ResizeObserver;

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
    this.ensureMapRenders();
    this.startRealtimeTracking();
  }

  ngOnDestroy(): void {
    if (this.unsubscribe) {
      this.unsubscribe();
    }
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

  focusResponder(reportId: string): void {
    const track = this.tracks.find((t) => t.reportId === reportId);
    if (!track || !this.map) return;
    this.selectedId = reportId;
    this.map.setView([track.responderLocationLat, track.responderLocationLng], 15, {
      animate: true,
    });
    this.highlightSelectedMarker();
  }

  get selectedTrack(): ResponderTrack | null {
    if (!this.selectedId) return null;
    return this.tracks.find((t) => t.reportId === this.selectedId) ?? null;
  }

  formatTimestamp(value?: Date | null): string {
    if (!value) return 'Unknown';
    return value.toLocaleString();
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
    const status = (value ?? '').toString().trim().toLowerCase();
    if (status === 'pending') return '#2563eb';
    if (status === 'responding') return '#ffc806';
    if (status === 'on scene' || status === 'on_scene' || status === 'onscene') return '#ac1b22';
    if (status === 'resolved' || status === 'approved') return '#00a458';
    if (status === 'flagged') return '#ac1b22';
    return '#6b7280';
  }

  getStatusTextColor(value?: string | null): string {
    const status = (value ?? '').toString().trim().toLowerCase();
    if (status === 'responding') return '#1f2937';
    return '#ffffff';
  }

  refreshTracking(): void {
    this.updateMarkers();
    this.ensureMapRenders();
    if (this.selectedId) {
      this.focusResponder(this.selectedId);
      return;
    }
    if (this.tracks.length > 0) {
      this.fitToResponders();
    }
  }

  fitToResponders(): void {
    if (!this.map || this.tracks.length === 0) return;
    const points: Array<[number, number]> = [];
    this.tracks.forEach((track) => {
      points.push([track.reportLocationLat, track.reportLocationLng]);
      points.push([track.responderLocationLat, track.responderLocationLng]);
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

  private toDate(value: any): Date | null {
    if (value && typeof value.toDate === 'function') {
      return value.toDate();
    }
    if (value instanceof Date) {
      return value;
    }
    return null;
  }

  private startRealtimeTracking(): void {
    const reportsRef = collection(db, 'reports');
    this.unsubscribe = onSnapshot(
      reportsRef,
      (snapshot) => {
        const nextTracks: ResponderTrack[] = [];
        snapshot.docs.forEach((doc) => {
          const data = doc.data() as any;
          const responderPoint =
            this.toLatLng(data?.responderLocation) ??
            (typeof data?.responderLocationLat === 'number' &&
            typeof data?.responderLocationLng === 'number'
              ? {
                  lat: data.responderLocationLat as number,
                  lng: data.responderLocationLng as number,
                }
              : null);
          if (!responderPoint) return;

          const reportPoint =
            this.toLatLng(data?.incidentLocation) ??
            this.toLatLng(data?.location) ??
            (typeof data?.locationLat === 'number' && typeof data?.locationLng === 'number'
              ? { lat: data.locationLat as number, lng: data.locationLng as number }
              : null);
          if (!reportPoint) return;

          let reporterPoint =
            this.toLatLng(data?.reporterLocation) ??
            (typeof data?.reporterLocationLat === 'number' &&
            typeof data?.reporterLocationLng === 'number'
              ? {
                  lat: data.reporterLocationLat as number,
                  lng: data.reporterLocationLng as number,
                }
              : null);

          const source = (data?.locationSource ?? '').toString().toLowerCase();
          if (!reporterPoint && source === 'current') {
            reporterPoint = reportPoint;
          }

          nextTracks.push({
            reportId: doc.id,
            responderName: data?.responderName ?? data?.responder ?? null,
            responderStatus: data?.responderStatus ?? data?.status ?? null,
            responderUnit: data?.responderUnit ?? null,
            responderId: data?.responderId ?? null,
            incidentType: data?.incidentType ?? null,
            reporterName: data?.name ?? null,
            barangay: data?.barangay ?? null,
            reportLocationLat: reportPoint.lat,
            reportLocationLng: reportPoint.lng,
            reporterLocationLat: reporterPoint?.lat ?? null,
            reporterLocationLng: reporterPoint?.lng ?? null,
            reporterLocationUpdatedAt: this.toDate(data?.reporterLocationUpdatedAt),
            responderLocationLat: responderPoint.lat,
            responderLocationLng: responderPoint.lng,
            responderLocationUpdatedAt: this.toDate(data?.responderLocationUpdatedAt),
            reportStatus: data?.status ?? null,
          });
        });

        this.ngZone.run(() => {
          this.tracks = nextTracks;
          this.isLoading = false;
          this.isListening = true;
          this.updateMarkers();
          if (!this.selectedId && this.tracks.length > 0) {
            this.selectedId = this.tracks[0].reportId;
            this.highlightSelectedMarker();
          }
        });
      },
      () => {
        this.ngZone.run(() => {
          this.mapLoadError = 'Unable to subscribe to responder updates.';
          this.isListening = false;
          this.isLoading = false;
        });
      },
    );
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
    const nextIds = new Set(this.tracks.map((track) => track.reportId));

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

    for (const track of this.tracks) {
      const reportExisting = this.reportMarkerByReportId.get(track.reportId);
      if (reportExisting) {
        reportExisting.setLatLng([track.reportLocationLat, track.reportLocationLng]);
      } else {
        const reportMarker = L.circleMarker([track.reportLocationLat, track.reportLocationLng], {
          radius: 7,
          color: '#AC1B22',
          fillColor: '#AC1B22',
          fillOpacity: 0.9,
          weight: 2,
        });
        reportMarker.on('click', () => {
          this.ngZone.run(() => this.focusResponder(track.reportId));
        });
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
            this.ngZone.run(() => this.focusResponder(track.reportId));
          });
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
          this.ngZone.run(() => this.focusResponder(track.reportId));
        });

        responderMarker.bindTooltip(
          `${track.responderName ?? 'Responder'} - ${track.responderStatus ?? 'Active'}`,
          {
            direction: 'top',
            offset: [0, -8],
          },
        );

        responderMarker.addTo(this.responderLayer);
        this.responderMarkerByReportId.set(track.reportId, responderMarker);
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
}

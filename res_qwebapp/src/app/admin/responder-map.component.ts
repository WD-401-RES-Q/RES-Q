import { AfterViewInit, Component, NgZone, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { collection, onSnapshot, Unsubscribe } from 'firebase/firestore';
import { db } from '../firebase.config';

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
})
export class ResponderMapComponent implements AfterViewInit, OnDestroy {
  tracks: ResponderTrack[] = [];
  selectedId: string | null = null;
  mapLoadError = '';
  isListening = false;
  isLoading = true;

  private map?: any;
  private responderLayer?: any;
  private geofenceCircle?: any;
  private unsubscribe?: Unsubscribe;
  private markerByReportId = new Map<string, any>();
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
    this.markerByReportId.clear();
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

  formatCoord(value?: number): string {
    if (value === undefined || value === null || Number.isNaN(value)) {
      return '—';
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
    const points = this.tracks.map((track) => [track.responderLocationLat, track.responderLocationLng]);
    const bounds = L.latLngBounds(points);
    this.map.fitBounds(bounds.pad(0.2));
  }

  hardRefresh(): void {
    const url = new URL(window.location.href);
    url.searchParams.set('refresh', Date.now().toString());
    window.location.replace(url.toString());
  }

  private startRealtimeTracking(): void {
    const reportsRef = collection(db, 'reports');
    this.unsubscribe = onSnapshot(
      reportsRef,
      (snapshot) => {
        const nextTracks: ResponderTrack[] = [];
        snapshot.docs.forEach((doc) => {
          const data = doc.data() as any;
          const loc = data?.responderLocation;
          let lat: number | null = null;
          let lng: number | null = null;
          if (loc && typeof loc.latitude === 'number' && typeof loc.longitude === 'number') {
            lat = loc.latitude;
            lng = loc.longitude;
          } else if (
            typeof data?.responderLocationLat === 'number' &&
            typeof data?.responderLocationLng === 'number'
          ) {
            lat = data.responderLocationLat;
            lng = data.responderLocationLng;
          }
          if (lat === null || lng === null) return;
          const updatedAt = data?.responderLocationUpdatedAt;
          const updatedDate =
            updatedAt && typeof updatedAt.toDate === 'function' ? updatedAt.toDate() : null;
          nextTracks.push({
            reportId: doc.id,
            responderName: data?.responderName ?? data?.responder ?? null,
            responderStatus: data?.responderStatus ?? data?.status ?? null,
            responderUnit: data?.responderUnit ?? null,
            responderId: data?.responderId ?? null,
            incidentType: data?.incidentType ?? null,
            reporterName: data?.name ?? null,
            barangay: data?.barangay ?? null,
            responderLocationLat: lat,
            responderLocationLng: lng,
            responderLocationUpdatedAt: updatedDate,
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
      }
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
    if (!this.map || !this.responderLayer) return;
    const nextIds = new Set(this.tracks.map((track) => track.reportId));

    for (const [reportId, marker] of this.markerByReportId.entries()) {
      if (!nextIds.has(reportId)) {
        this.responderLayer.removeLayer(marker);
        this.markerByReportId.delete(reportId);
      }
    }

    for (const track of this.tracks) {
      const existing = this.markerByReportId.get(track.reportId);
      if (existing) {
        existing.setLatLng([track.responderLocationLat, track.responderLocationLng]);
        continue;
      }

      const marker = L.circleMarker(
        [track.responderLocationLat, track.responderLocationLng],
        {
          radius: 8,
          color: '#0B5FFF',
          fillColor: '#0B5FFF',
          fillOpacity: 0.9,
          weight: 2,
        }
      );

      marker.on('click', () => {
        this.ngZone.run(() => this.focusResponder(track.reportId));
      });

      marker.bindTooltip(
        `${track.responderName ?? 'Responder'} · ${track.responderStatus ?? 'Active'}`,
        {
          direction: 'top',
          offset: [0, -8],
        }
      );

      marker.addTo(this.responderLayer);
      this.markerByReportId.set(track.reportId, marker);
    }

    this.highlightSelectedMarker();
  }

  private highlightSelectedMarker(): void {
    for (const [reportId, marker] of this.markerByReportId.entries()) {
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

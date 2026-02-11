import { Injectable } from '@angular/core';

export interface ReportImageSourceInput {
  mediaUrl?: string | null;
  mediaPath?: string | null;
  mediaThumbUrl?: string | null;
  mediaThumbPath?: string | null;
  mediaThumbWebpUrl?: string | null;
  mediaThumbWebpPath?: string | null;
}

export interface ReportImageSourceSet {
  image: string;
  imageThumb?: string;
  imageThumbWebp?: string;
}

@Injectable({
  providedIn: 'root'
})
export class FirebaseStorageService {
  private readonly bucket = 'res-q-93ca6.firebasestorage.app';
  private readonly placeholder = 'assets/images/placeholder-report.jpg';

  /**
   * Converts a Firebase Storage path to a download URL
   * @param storagePath Path like 'reports/report-id/image.jpg'
   * @returns Download URL or a data URL for blob data
   */
  getDownloadUrl(storagePath: string | null | undefined): string {
    return this.toDownloadUrl(storagePath) ?? this.placeholder;
  }

  getReportImageSources(input: ReportImageSourceInput): ReportImageSourceSet {
    const mediaPath = (input.mediaPath ?? '').toString().trim();
    const derivedThumbs = this.deriveThumbPaths(mediaPath);

    const image =
      this.toDownloadUrl(input.mediaUrl) ??
      this.toDownloadUrl(input.mediaPath) ??
      this.placeholder;

    let imageThumb =
      this.toDownloadUrl(input.mediaThumbUrl) ??
      this.toDownloadUrl(input.mediaThumbPath) ??
      this.toDownloadUrl(derivedThumbs.jpegPath) ??
      undefined;

    let imageThumbWebp =
      this.toDownloadUrl(input.mediaThumbWebpUrl) ??
      this.toDownloadUrl(input.mediaThumbWebpPath) ??
      this.toDownloadUrl(derivedThumbs.webpPath) ??
      undefined;

    if (!imageThumbWebp && imageThumb && imageThumb.toLowerCase().includes('.webp')) {
      imageThumbWebp = imageThumb;
      imageThumb = undefined;
    }

    return {
      image,
      imageThumb,
      imageThumbWebp,
    };
  }

  private toDownloadUrl(storagePath: string | null | undefined): string | null {
    const raw = (storagePath ?? '').toString().trim();
    if (!raw) return null;

    if (raw.startsWith('http')) {
      return raw;
    }

    const encodedPath = encodeURIComponent(raw);
    return `https://firebasestorage.googleapis.com/v0/b/${this.bucket}/o/${encodedPath}?alt=media`;
  }

  private deriveThumbPaths(mediaPath: string): { webpPath?: string; jpegPath?: string } {
    if (!mediaPath || mediaPath.startsWith('http')) {
      return {};
    }
    if (!mediaPath.startsWith('reports/') || mediaPath.startsWith('reports/thumbs/')) {
      return {};
    }

    const fileName = mediaPath.split('/').pop();
    if (!fileName) {
      return {};
    }
    const lastDot = fileName.lastIndexOf('.');
    const baseName = lastDot > 0 ? fileName.slice(0, lastDot) : fileName;
    if (!baseName) {
      return {};
    }

    return {
      webpPath: `reports/thumbs/${baseName}_640.webp`,
      jpegPath: `reports/thumbs/${baseName}_640.jpg`,
    };
  }
}

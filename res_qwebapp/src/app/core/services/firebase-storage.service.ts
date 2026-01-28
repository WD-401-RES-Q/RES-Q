import { Injectable } from '@angular/core';
import { getStorage, ref, getBytes } from 'firebase/storage';
import { app } from '../config/firebase.config';

@Injectable({
  providedIn: 'root'
})
export class FirebaseStorageService {
  private storage = getStorage(app);

  /**
   * Converts a Firebase Storage path to a download URL
   * @param storagePath Path like 'reports/report-id/image.jpg'
   * @returns Download URL or a data URL for blob data
   */
  getDownloadUrl(storagePath: string | null | undefined): string {
    if (!storagePath) {
      return 'assets/images/placeholder-report.jpg';
    }

    // If it's already a full URL, return as is
    if (storagePath.startsWith('http')) {
      return storagePath;
    }

    // If it's a storage path, construct the download URL
    // Firebase Storage download URL format: https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{path}?alt=media
    const bucket = 'res-q-93ca6.firebasestorage.app';
    const encodedPath = encodeURIComponent(storagePath);
    return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodedPath}?alt=media`;
  }
}

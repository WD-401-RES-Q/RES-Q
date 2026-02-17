import { Component, OnInit, NgZone, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { FirestoreService } from '../../../core/services/firestore.service';
import { getDownloadURL, getStorage, ref, uploadBytes } from 'firebase/storage';
import { app } from '../../../core/config/firebase.config';

type AdminAnnouncement = {
  id: string;
  title: string;
  content: string;
  priority: 'Normal' | 'Important' | 'Critical';
  createdAt: Date;
  imageUrl?: string;
};

@Component({
  selector: 'app-announcements',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './announcements.html',
  styleUrls: ['./announcements.component.scss'],
})
export class AnnouncementsComponent implements OnInit {
  title = '';
  content = '';
  priority: AdminAnnouncement['priority'] = 'Normal';
  imageUrl = '';
  isPublishing = false;
  posts: AdminAnnouncement[] = [];
  showSuccessModal = false;
  showDeleteModal = false;
  isDeletingAnnouncement = false;
  expandedImageUrl = '';
  announcementToDelete: AdminAnnouncement | null = null;

  selectedImageFile: File | null = null;
  selectedImagePreview = '';
  private storage = getStorage(app);

  constructor(
    private firestoreService: FirestoreService,
    private ngZone: NgZone,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    void this.initializeAnnouncements();
  }

  get canPublish(): boolean {
    return this.title.trim().length > 0 && this.content.trim().length > 0;
  }

  async publish(): Promise<void> {
    if (!this.canPublish || this.isPublishing) return;
    this.updateUi(() => {
      this.isPublishing = true;
    });

    const createdAt = new Date();
    let finalImageUrl = this.imageUrl.trim();

    try {
      if (this.selectedImageFile) {
        finalImageUrl = await this.withTimeout(
          this.uploadAnnouncementImage(this.selectedImageFile),
          10000,
          'Upload announcement image',
        );
      }
    } catch (error) {
      console.error('Failed to upload image:', error);
        this.updateUi(() => {
          this.isPublishing = false;
        });
      return;
    }

    try {
      // Persist to Firestore for mobile notifications
      const announcementId = await this.withTimeout(
        this.firestoreService.addDocument('announcements', {
          title: this.title.trim(),
          content: this.content.trim(),
          priority: this.priority,
          imageUrl: finalImageUrl || '',
          isPlaceholder: false,
        }),
        8000,
        'Publish announcement',
      );

      this.updateUi(() => {
        this.posts.unshift({
          id: announcementId,
          title: this.title.trim(),
          content: this.content.trim(),
          priority: this.priority,
          createdAt,
          imageUrl: finalImageUrl || undefined,
        });
      });

      // Reset form only after a successful publish
      this.updateUi(() => {
        this.title = '';
        this.content = '';
        this.priority = 'Normal';
        this.imageUrl = '';
        this.selectedImageFile = null;
        this.selectedImagePreview = '';
        this.showSuccessModal = true;
      });
      await this.loadAnnouncements();
    } catch (error) {
      console.error('Failed to publish announcement:', error);
    } finally {
      this.updateUi(() => {
        this.isPublishing = false;
      });
    }
  }

  private updateUi(mutator: () => void): void {
    this.ngZone.run(() => {
      mutator();
      this.cdr.detectChanges();
    });
  }

  onSelectImage(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    this.selectedImageFile = file;
    this.imageUrl = file.name;
    const reader = new FileReader();
    reader.onload = () => {
      this.updateUi(() => {
        this.selectedImagePreview = reader.result as string;
      });
    };
    reader.readAsDataURL(file);
  }

  clearSelectedImage(): void {
    this.selectedImageFile = null;
    this.selectedImagePreview = '';
    this.imageUrl = '';
  }

  openImagePreview(url: string): void {
    if (!url) return;
    this.expandedImageUrl = url;
  }

  closeImagePreview(): void {
    this.expandedImageUrl = '';
  }

  closeSuccessModal(): void {
    this.showSuccessModal = false;
  }

  requestDeleteAnnouncement(post: AdminAnnouncement): void {
    if (this.isDeletingAnnouncement) {
      return;
    }
    this.announcementToDelete = post;
    this.showDeleteModal = true;
    this.cdr.markForCheck();
  }

  cancelDeleteAnnouncement(): void {
    if (this.isDeletingAnnouncement) {
      return;
    }
    this.showDeleteModal = false;
    this.announcementToDelete = null;
    this.cdr.markForCheck();
  }

  async confirmDeleteAnnouncement(): Promise<void> {
    if (this.isDeletingAnnouncement) {
      return;
    }

    const target = this.announcementToDelete;
    if (!target?.id) {
      console.error('Missing announcement id, cannot delete');
      this.cancelDeleteAnnouncement();
      return;
    }

    const adminId = this.getCurrentAdminId();
    if (!adminId) {
      console.error('Missing admin id, cannot delete announcement');
      this.cancelDeleteAnnouncement();
      return;
    }

    this.isDeletingAnnouncement = true;
    this.cdr.markForCheck();

    try {
      await this.withTimeout(
        this.firestoreService.deleteAnnouncementAsAdmin(target.id, adminId),
        12000,
        'Delete announcement',
      );
      this.updateUi(() => {
        this.posts = this.posts.filter((post) => post.id !== target.id);
      });
    } catch (error) {
      console.error('Failed to delete announcement:', error);
    } finally {
      this.isDeletingAnnouncement = false;
      this.showDeleteModal = false;
      this.announcementToDelete = null;
      this.cdr.markForCheck();
    }
  }

  private getCurrentAdminId(): string {
    try {
      const raw = localStorage.getItem('currentAdmin');
      if (!raw) {
        return '';
      }
      const parsed = JSON.parse(raw) as { id?: unknown };
      return typeof parsed.id === 'string' ? parsed.id.trim() : '';
    } catch (error) {
      console.error('Failed to read current admin id:', error);
      return '';
    }
  }

  private async uploadAnnouncementImage(file: File): Promise<string> {
    const fileExt = file.name.split('.').pop() || 'jpg';
    const fileRef = ref(
      this.storage,
      `announcements/${Date.now()}_${Math.random().toString(36).slice(2)}.${fileExt}`,
    );
    await uploadBytes(fileRef, file);
    return getDownloadURL(fileRef);
  }

  private async ensureAnnouncementsCollection(): Promise<void> {
    try {
      const existing = await this.withTimeout(
        this.firestoreService.getCollection('announcements'),
        6000,
        'Load announcements',
      );
      if (existing.length > 0) return;
      await this.withTimeout(
        this.firestoreService.addDocument('announcements', {
          title: 'Welcome',
          content: 'This is a placeholder announcement.',
          priority: 'Normal',
          imageUrl: '',
          isPlaceholder: true,
        }),
        8000,
        'Create placeholder announcement',
      );
    } catch (error) {
      console.error('Failed to ensure announcements collection:', error);
    }
  }

  private async initializeAnnouncements(): Promise<void> {
    await this.ensureAnnouncementsCollection();
    await this.loadAnnouncements();
  }

  private async loadAnnouncements(): Promise<void> {
    try {
      const docs = await this.withTimeout(
        this.firestoreService.getCollection('announcements'),
        8000,
        'Load announcements list',
      );

      const announcements = docs
        .filter((doc) => doc.isPlaceholder !== true)
        .map((doc) => this.mapAnnouncement(doc))
        .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());

      this.updateUi(() => {
        this.posts = announcements;
      });
    } catch (error) {
      console.error('Failed to load announcements list:', error);
    }
  }

  private mapAnnouncement(doc: any): AdminAnnouncement {
    const createdAtRaw = doc.createdAt;
    let createdAt = new Date();
    if (createdAtRaw instanceof Date) {
      createdAt = createdAtRaw;
    } else if (
      createdAtRaw &&
      typeof createdAtRaw.toDate === 'function'
    ) {
      createdAt = createdAtRaw.toDate();
    } else if (typeof createdAtRaw === 'string' || typeof createdAtRaw === 'number') {
      const parsed = new Date(createdAtRaw);
      if (!isNaN(parsed.getTime())) {
        createdAt = parsed;
      }
    }

    const priorityRaw = (doc.priority ?? 'Normal').toString();
    const priority: AdminAnnouncement['priority'] =
      priorityRaw === 'Critical' || priorityRaw === 'Important'
        ? priorityRaw
        : 'Normal';

    const imageUrl =
      typeof doc.imageUrl === 'string' && doc.imageUrl.trim().length > 0
        ? doc.imageUrl.trim()
        : undefined;

    return {
      id: (doc.id ?? '').toString(),
      title: (doc.title ?? '').toString(),
      content: (doc.content ?? '').toString(),
      priority,
      createdAt,
      imageUrl,
    };
  }

  private withTimeout<T>(
    promise: Promise<T>,
    ms: number,
    label: string,
  ): Promise<T> {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        reject(new Error(`${label} timed out after ${ms}ms`));
      }, ms);
      promise
        .then((value) => {
          clearTimeout(timer);
          resolve(value);
        })
        .catch((error) => {
          clearTimeout(timer);
          reject(error);
        });
    });
  }

  getPreviewImage(post: AdminAnnouncement): string {
    if (post.imageUrl && post.imageUrl.trim().length > 0) {
      return post.imageUrl;
    }
    switch (post.priority) {
      case 'Critical':
        return 'assets/images/NOTIF-3.png';
      case 'Important':
        return 'assets/images/NOTIF-2.png';
      default:
        return 'assets/images/NOTIF-1.png';
    }
  }
}

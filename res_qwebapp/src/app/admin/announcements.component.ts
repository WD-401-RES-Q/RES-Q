import { Component, OnInit, NgZone, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { FirestoreService } from '../firestore.service';
import { getDownloadURL, getStorage, ref, uploadBytes } from 'firebase/storage';
import { app } from '../firebase.config';

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
})
export class AnnouncementsComponent implements OnInit {
  title = '';
  content = '';
  priority: AdminAnnouncement['priority'] = 'Normal';
  imageUrl = '';
  isPublishing = false;
  posts: AdminAnnouncement[] = [];
  showSuccessModal = false;

  selectedImageFile: File | null = null;
  selectedImagePreview = '';
  private storage = getStorage(app);

  constructor(
    private firestoreService: FirestoreService,
    private ngZone: NgZone,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.ensureAnnouncementsCollection();
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

    const newPost: AdminAnnouncement = {
      id: Math.random().toString(36).slice(2),
      title: this.title.trim(),
      content: this.content.trim(),
      priority: this.priority,
      createdAt,
      imageUrl: finalImageUrl || undefined,
    };
    this.updateUi(() => {
      this.posts.unshift(newPost);
    });

    try {
      // Persist to Firestore for mobile notifications
      await this.withTimeout(
        this.firestoreService.addDocument('announcements', {
          title: newPost.title,
          content: newPost.content,
          priority: newPost.priority,
          imageUrl: newPost.imageUrl ?? '',
          isPlaceholder: false,
        }),
        8000,
        'Publish announcement',
      );

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
    const reader = new FileReader();
    reader.onload = () => {
      this.selectedImagePreview = reader.result as string;
    };
    reader.readAsDataURL(file);
  }

  clearSelectedImage(): void {
    this.selectedImageFile = null;
    this.selectedImagePreview = '';
  }

  closeSuccessModal(): void {
    this.showSuccessModal = false;
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

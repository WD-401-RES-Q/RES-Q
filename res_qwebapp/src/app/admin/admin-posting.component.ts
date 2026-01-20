import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

type AdminPost = {
  id: string;
  title: string;
  content: string;
  priority: 'Normal' | 'Important' | 'Critical';
  createdAt: Date;
};

@Component({
  selector: 'app-admin-posting',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './admin-posting.html',
})
export class AdminPostingComponent {
  title = '';
  content = '';
  priority: AdminPost['priority'] = 'Normal';
  isPublishing = false;
  posts: AdminPost[] = [];

  get canPublish(): boolean {
    return this.title.trim().length > 0 && this.content.trim().length > 0;
  }

  publish(): void {
    if (!this.canPublish || this.isPublishing) return;
    this.isPublishing = true;

    // Front-end only: simulate publish by adding to local list
    const newPost: AdminPost = {
      id: Math.random().toString(36).slice(2),
      title: this.title.trim(),
      content: this.content.trim(),
      priority: this.priority,
      createdAt: new Date(),
    };
    this.posts.unshift(newPost);

    // Reset form
    this.title = '';
    this.content = '';
    this.priority = 'Normal';
    setTimeout(() => (this.isPublishing = false), 300);
  }
}

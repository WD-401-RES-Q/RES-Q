import { Component, signal, OnInit, inject } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { getApp } from 'firebase/app';
import { FirestoreService } from './firestore.service';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet],
  templateUrl: './app.html',
  styleUrl: './app.css'
})
export class App implements OnInit {
  protected readonly title = signal('res_qwebapp');
  private firestoreService = inject(FirestoreService);

  ngOnInit() {
    console.log('=== APP COMPONENT INITIALIZED ===');
    console.log('FirestoreService injected and initialized');
    console.log('Firebase projectId:', getApp().options.projectId);
  }
}

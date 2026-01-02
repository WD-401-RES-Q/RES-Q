import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { FirestoreService } from '../firestore.service';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

@Component({
  standalone: true,
  selector: 'app-admin-layout',
  imports: [CommonModule, RouterModule],
  templateUrl: './admin-layout.html',
  styleUrls: ['./admin-layout.css']
})
export class AdminLayoutComponent implements OnInit {
  pendingReportsCount$!: Observable<number>;
  flaggedReportsCount$!: Observable<number>;
  unverifiedAccountsCount$!: Observable<number>;

  constructor(private firestoreService: FirestoreService) {}

  ngOnInit() {
    // Map observables to counts
    this.unverifiedAccountsCount$ = this.firestoreService.pendingUsers$.pipe(
      map(users => users.length)
    );

    // TODO: Add pending and flagged reports observables when available
    // For now, use placeholder values
    this.pendingReportsCount$ = new Observable(observer => observer.next(0));
    this.flaggedReportsCount$ = new Observable(observer => observer.next(0));
  }
}

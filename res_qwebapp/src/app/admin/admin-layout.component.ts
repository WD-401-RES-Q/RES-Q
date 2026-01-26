import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { FirestoreService } from '../firestore.service';
import { AuthService } from '../services/auth.service';
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

  constructor(
    private firestoreService: FirestoreService,
    public authService: AuthService
  ) {}

  ngOnInit() {
    // Map observables to counts
    this.unverifiedAccountsCount$ = this.firestoreService.pendingUsers$.pipe(
      map(users => users.length)
    );

    // Pending reports count
    this.pendingReportsCount$ = this.firestoreService.pendingReports$.pipe(
      map(reports => reports.length)
    );

    // Flagged reports count
    this.flaggedReportsCount$ = this.firestoreService.flaggedReports$.pipe(
      map(reports => reports.length)
    );
  }

  logout() {
    this.authService.logout();
  }
}

import { Routes } from '@angular/router';
import { AdminLayoutComponent } from '../features/admin/layout/admin-layout.component';
import { DashboardComponent } from '../features/admin/dashboard/dashboard.component';
import { ReportsComponent } from '../features/admin/reports/reports.component';
import { AccountsComponent } from '../features/admin/accounts/accounts.component';
import { UnverifiedAccountsComponent } from '../features/admin/unverified-accounts/unverified-accounts.component';
import { SettingsComponent } from '../features/admin/settings/settings.component';
import { AnnouncementsComponent } from '../features/admin/announcements/announcements.component';
import { AdminLoginComponent } from '../features/admin/auth/login.component';
import { ResponderMapComponent } from '../features/admin/responder-map/responder-map.component';
import { authGuard } from './guards/auth.guard';

export const routes: Routes = [
  { path: '', redirectTo: 'admin/login', pathMatch: 'full' },
  { path: 'admin/login', component: AdminLoginComponent },
  {
    path: 'admin',
    component: AdminLayoutComponent,
    canActivate: [authGuard],
    children: [
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
      { path: 'dashboard', component: DashboardComponent },
      { path: 'reports', component: ReportsComponent },
      { path: 'responder-map', component: ResponderMapComponent },
      { path: 'announcements', component: AnnouncementsComponent },
      { path: 'accounts', component: AccountsComponent },
      { path: 'unverified-accounts', component: UnverifiedAccountsComponent },
      { path: 'settings', component: SettingsComponent },
    ],
  },
];

import { Routes } from '@angular/router';
import { AdminLayoutComponent } from './admin/admin-layout.component';
import { DashboardComponent } from './admin/dashboard.component';
import { ReportsComponent } from './admin/reports.component';
import { AccountsComponent } from './admin/accounts.component';
import { UnverifiedAccountsComponent } from './admin/unverified-accounts.component';
import { SettingsComponent } from './admin/settings.component';
import { AdminPostingComponent } from './admin/admin-posting.component';
import { AdminLoginComponent } from './admin/login.component';
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
      { path: 'announcements', component: AdminPostingComponent },
      { path: 'accounts', component: AccountsComponent },
      { path: 'unverified-accounts', component: UnverifiedAccountsComponent },
      { path: 'settings', component: SettingsComponent },
    ],
  },
];

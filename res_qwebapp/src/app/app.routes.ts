import { Routes } from '@angular/router';
import { AdminLayoutComponent } from './admin/admin-layout.component';
import { DashboardComponent } from './admin/dashboard.component';
import { PendingReportsComponent } from './admin/pending-reports.component';
import { ApprovedReportsComponent } from './admin/approved-reports.component';
import { FlaggedReportsComponent } from './admin/flagged-reports.component';
import { AccountsComponent } from './admin/accounts.component';
import { UnverifiedAccountsComponent } from './admin/unverified-accounts.component';
import { SettingsComponent } from './admin/settings.component';

export const routes: Routes = [
  { path: '', redirectTo: 'admin', pathMatch: 'full' },
  {
    path: 'admin',
    component: AdminLayoutComponent,
    children: [
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
      { path: 'dashboard', component: DashboardComponent },
      { path: 'pending-reports', component: PendingReportsComponent },
      { path: 'approved-reports', component: ApprovedReportsComponent },
      { path: 'flagged-reports', component: FlaggedReportsComponent },
      { path: 'accounts', component: AccountsComponent },
      { path: 'unverified-accounts', component: UnverifiedAccountsComponent },
      { path: 'settings', component: SettingsComponent },
    ],
  },
];

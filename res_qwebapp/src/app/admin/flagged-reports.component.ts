import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

interface FlaggedReport {
  id: number;
  category: string;
  reason: string;
  location: string;
  flaggedBy: string;
  date: string;
  time: string;
  imageUrl: string;
}

@Component({
  selector: 'app-flagged-reports',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './flagged-reports.html',
})
export class FlaggedReportsComponent {
  reports: FlaggedReport[] = [
    {
      id: 1,
      category: 'Road Obstruction',
      reason: 'Flagged due to incorrect or misleading report data.',
      location: 'Friendship Highway, Angeles City',
      flaggedBy: 'System Auto-Flag',
      date: 'Nov 22, 2025',
      time: '4:18 PM',
      imageUrl: 'assets/images/pothole2.jpg', // UPDATED IMAGE
    },
  ];

  revert(report: FlaggedReport) {
    console.log('Reverted flagged report:', report);
    alert(`Report reverted: ${report.category}`);
  }
}

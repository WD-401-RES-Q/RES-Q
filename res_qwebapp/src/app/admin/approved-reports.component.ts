import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

interface ApprovedReport {
  id: number;
  category: string;
  type: string;
  location: string;
  approvedBy: string;
  date: string;
  time: string;
  imageUrl: string;
}

@Component({
  selector: 'app-approved-reports',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './approved-reports.html',
})
export class ApprovedReportsComponent {
  reports: ApprovedReport[] = [
    {
      id: 1,
      category: 'Road Obstruction',
      type: 'Pothole',
      location: 'Pandan Road, Angeles City',
      approvedBy: 'Admin 01',
      date: 'Nov 22, 2025',
      time: '2:05 PM',
      imageUrl: 'assets/images/pothole2.jpg', 
    },
  ];

  revert(report: ApprovedReport) {
    console.log('Reverted approved report:', report);
    alert(`Reverted: ${report.category} (${report.type})`);
  }
}

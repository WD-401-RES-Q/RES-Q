import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

interface PendingReport {
  id: number;
  title: string;
  category: string;
  location: string;
  date: string;
  time: string;
  reporter: string;
  description: string;
  image: string;
}

@Component({
  selector: 'app-pending-reports',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './pending-reports.html',
})
export class PendingReportsComponent {
  reports: PendingReport[] = [
    {
      id: 1,
      title: 'Vehicular Accident',
      category: 'Vehicular Emergencies',
      location: 'MacArthur Highway, Angeles City',
      date: 'Oct 12, 2025',
      time: '09:10 AM',
      reporter: 'Juan Dela Cruz',
      description:
        'Two-car collision near the intersection. Minor injuries reported. Road partially blocked.',
      image: 'assets/images/vehicularaccident.jpg',
    },
    {
      id: 2,
      title: 'Large Pothole on Main Road',
      category: 'Road Obstruction',
      location: 'Friendship Avenue, Angeles City',
      date: 'Oct 10, 2025',
      time: '06:45 PM',
      reporter: 'Maria Santos',
      description:
        'Deep pothole forming on right lane. Vehicles swerving to avoid it, increasing risk for accidents.',
      image: 'assets/images/pothole.webp',
    },
  ];

  approve(report: PendingReport) {
    console.log('Approved report:', report.id);
    alert(`Approved: ${report.title}`);
  }

  reject(report: PendingReport) {
    console.log('Rejected report:', report.id);
    alert(`Rejected: ${report.title}`);
  }
}

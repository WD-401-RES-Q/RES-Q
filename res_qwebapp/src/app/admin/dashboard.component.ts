import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NgChartsModule } from 'ng2-charts';
import { ChartConfiguration, ChartOptions } from 'chart.js';
import 'chart.js/auto';

// FontAwesome
import { FontAwesomeModule } from '@fortawesome/angular-fontawesome';
import {
  faKitMedical,
  faCarBurst,
  faFire,
  faTriangleExclamation,
  faCloudBolt,
} from '@fortawesome/free-solid-svg-icons';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, NgChartsModule, FontAwesomeModule],
  templateUrl: './dashboard.html',
})
export class DashboardComponent {
  // TOP SUMMARY NUMBERS (mock for now)
  totalReports = 240;
  approvedReports = 200;
  flaggedReports = 5;

  // CATEGORY CARDS (mock)
  medicalEmergencies = 67;
  vehicularEmergencies = 58;
  fireEmergencies = 9;
  roadObstructions = 14;
  naturalHazards = 11;

  // FontAwesome icons
  faMedical = faKitMedical;
  faVehicular = faCarBurst;
  faFire = faFire;
  faRoad = faTriangleExclamation;
  faHazard = faCloudBolt;

  // TIME RANGE DROPDOWN
  selectedTimeRange = 'Today';
  timeRanges = ['Today', 'This Week', 'This Month', 'All time'];

  // LINE CHART DATA (mock)
  lineChartData: ChartConfiguration<'line'>['data'] = {
    labels: ['08:00', '10:00', '12:00', '14:00', '16:00', '18:00'],
    datasets: [
      {
        data: [3, 10, 18, 22, 30, 35],
        label: 'Total Reports',
        tension: 0.3,
        fill: true,
        borderColor: '#AC1B22',                  // red line
        backgroundColor: 'rgba(172,27,34,0.12)', // light red fill
        pointBackgroundColor: '#FFC806',         // yellow points
        pointBorderColor: '#AC1B22',
        pointRadius: 4,
        pointHoverRadius: 6,
      },
    ],
  };

  // CHART OPTIONS (tooltips included)
  lineChartOptions: ChartOptions<'line'> = {
    responsive: true,
    plugins: {
      legend: {
        display: false,
      },
      tooltip: {
        enabled: true,
      },
    },
    scales: {
      x: {
        ticks: { color: '#555' },
        grid: { color: '#eeeeee' },
      },
      y: {
        beginAtZero: true,
        ticks: { color: '#555' },
        grid: { color: '#eeeeee' },
      },
    },
  };

  onTimeRangeChange(value: string) {
    this.selectedTimeRange = value;
    // later: call backend and update lineChartData here
  }
}

import { Component, OnDestroy, OnInit, ViewChild, ElementRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NgChartsModule } from 'ng2-charts';
import { ChartConfiguration, ChartOptions } from 'chart.js';
import 'chart.js/auto';
import { FirestoreService } from '../firestore.service';
import { Subscription } from 'rxjs';
import jsPDF from 'jspdf';
import html2canvas from 'html2canvas';

// FontAwesome
import { FontAwesomeModule } from '@fortawesome/angular-fontawesome';
import {
  faKitMedical,
  faCarBurst,
  faFire,
  faTriangleExclamation,
  faCloudBolt,
  faPrint,
} from '@fortawesome/free-solid-svg-icons';

type ReportRecord = {
  reportedAt?: any;
  createdAt?: any;
  timestamp?: any;
  [key: string]: any;
};

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, NgChartsModule, FontAwesomeModule],
  templateUrl: './dashboard.html',
})
export class DashboardComponent implements OnInit, OnDestroy {
  constructor(private firestoreService: FirestoreService) {}

  // TOP SUMMARY NUMBERS
  totalReports = 0;
  approvedReports = 0;
  flaggedReports = 0;

  // CATEGORY CARDS (live counts)
  otherEmergencies = 0;
  vehicularEmergencies = 0;
  fireEmergencies = 0;
  roadObstructions = 0;
  naturalHazards = 0;

  // FontAwesome icons
  faOther = faKitMedical;
  faVehicular = faCarBurst;
  faFire = faFire;
  faRoad = faTriangleExclamation;
  faHazard = faCloudBolt;
  faPrint = faPrint;

  // TIME RANGE DROPDOWN
  selectedTimeRange = 'Today';
  timeRanges = ['Today', 'This Week', 'This Month', 'All time'];

  // CATEGORY FILTER DROPDOWN
  selectedCategory = 'Total Reports';
  categories = [
    'Total Reports',
    'Other Emergencies',
    'Vehicular Emergencies',
    'Fire Emergencies',
    'Road Obstruction',
    'Natural Hazards'
  ];

  // Current date for PDF
  currentDate = new Date();

  // BAR CHART DATA (dynamic)
  barChartData: ChartConfiguration<'bar'>['data'] = {
    labels: [],
    datasets: [
      {
        data: [],
        label: 'Total Reports',
        backgroundColor: '#AC1B22',
        borderRadius: 6,
      },
    ],
  };

  // CHART OPTIONS (tooltips included)
  barChartOptions: ChartOptions<'bar'> = {
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
        ticks: { color: '#555', font: { family: 'Roboto' } },
        grid: { color: '#eeeeee' },
        title: {
          display: true,
          text: 'Time Period',
          color: '#212121',
          font: {
            size: 14,
            weight: 'bold',
            family: 'Roboto'
          }
        }
      },
      y: {
        beginAtZero: true,
        ticks: { color: '#555', font: { family: 'Roboto' } },
        grid: { color: '#eeeeee' },
        title: {
          display: true,
          text: 'Number of Reports',
          color: '#212121',
          font: {
            size: 14,
            weight: 'bold',
            family: 'Roboto'
          }
        }
      },
    },
  };

  private allReports: ReportRecord[] = [];
  private sub?: Subscription;

  onTimeRangeChange(value: string) {
    this.selectedTimeRange = value;
    this.updateChartForRange();
  }

  onCategoryChange(value: string) {
    this.selectedCategory = value;
    this.updateChartForRange();
  }

  async ngOnInit() {
    this.sub = this.firestoreService.reports$.subscribe({
      next: (reports) => {
        this.allReports = reports;
        this.totalReports = reports.length;
        this.computeStatusCounts(reports);
        this.computeCategoryCounts(reports);
        this.updateChartForRange();
      },
      error: (err) => {
        console.error('Failed to load reports:', err);
        this.allReports = [];
        this.totalReports = 0;
        this.approvedReports = 0;
        this.flaggedReports = 0;
        this.resetCategoryCounts();
        this.updateChartForRange();
      },
    });
  }

  ngOnDestroy() {
    if (this.sub) this.sub.unsubscribe();
  }

  private resetCategoryCounts() {
    this.otherEmergencies = 0;
    this.vehicularEmergencies = 0;
    this.fireEmergencies = 0;
    this.roadObstructions = 0;
    this.naturalHazards = 0;
  }

  private computeStatusCounts(reports: ReportRecord[]) {
    this.approvedReports = 0;
    this.flaggedReports = 0;

    reports.forEach((report) => {
      const status = (report['status'] ?? '').toString().trim().toLowerCase();
      if (!status) return;
      if (status === 'approved' || status === 'resolved') {
        this.approvedReports += 1;
      }
      if (status === 'flagged') {
        this.flaggedReports += 1;
      }
    });
  }

  private computeCategoryCounts(reports: ReportRecord[]) {
    this.resetCategoryCounts();
    reports.forEach((report) => {
      const rawType = (report['incidentType'] ?? report['incident_type'] ?? report['type'] ?? '').toString();
      const type = rawType.trim().toLowerCase();

      if (!type) return;

      if (type.includes('fire')) {
        this.fireEmergencies += 1;
        return;
      }

      if (type.includes('vehic') || type.includes('car') || type.includes('traffic')) {
        this.vehicularEmergencies += 1;
        return;
      }

      if (type.includes('other')) {
        this.otherEmergencies += 1;
        return;
      }

      if (type.includes('road') || type.includes('obstruction') || type.includes('block')) {
        this.roadObstructions += 1;
        return;
      }

      if (
        type.includes('flood') ||
        type.includes('earthquake') ||
        type.includes('quake') ||
        type.includes('storm') ||
        type.includes('typhoon') ||
        type.includes('hazard') ||
        type.includes('landslide')
      ) {
        this.naturalHazards += 1;
        return;
      }
    });
  }

  private updateChartForRange() {
    const { labels, data } = this.buildChartData(this.selectedTimeRange, this.selectedCategory);
    const backgroundColor = this.getCategoryColor(this.selectedCategory);
    const xAxisLabel = this.getXAxisLabel(this.selectedTimeRange);
    
    this.barChartData = {
      labels,
      datasets: [
        {
          data,
          label: this.selectedCategory,
          backgroundColor,
          borderRadius: 6,
        },
      ],
    };

    // Update x-axis title
    if (this.barChartOptions.scales?.['x']?.title) {
      this.barChartOptions.scales['x'].title.text = xAxisLabel;
    }
  }

  private getXAxisLabel(range: string): string {
    switch (range) {
      case 'Today': return 'Hour';
      case 'This Week': return 'Day of Week';
      case 'This Month': return 'Day of Month';
      case 'All time': return 'Month';
      default: return 'Time Period';
    }
  }

  private getCategoryColor(category: string): string {
    switch (category) {
      case 'Other Emergencies': return '#00a458';
      case 'Vehicular Emergencies': return '#f09002';
      case 'Fire Emergencies': return '#ac1b22';
      case 'Road Obstruction': return '#ffc806';
      case 'Natural Hazards': return 'rgb(60, 131, 237)';
      default: return '#AC1B22';
    }
  }

  private buildChartData(range: string, category: string): { labels: string[]; data: number[] } {
    const now = new Date();
    const filteredReports = this.filterReportsByCategory(this.allReports, category);
    const reportsWithDate = filteredReports
      .map((r) => this.coerceReportDate(r))
      .filter((r): r is { date: Date } => !!r.date);

    if (range === 'Today') {
      const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      const end = new Date(start);
      end.setDate(end.getDate() + 1);

      const counts = new Array(24).fill(0);
      reportsWithDate.forEach(({ date }) => {
        if (date >= start && date < end) {
          counts[date.getHours()] += 1;
        }
      });

      const labels = counts.map((_, i) => `${i.toString().padStart(2, '0')}:00`);
      return { labels, data: counts };
    }

    if (range === 'This Week') {
      const day = now.getDay(); // 0 (Sun) - 6 (Sat)
      const mondayOffset = (day + 6) % 7;
      const start = new Date(now);
      start.setDate(now.getDate() - mondayOffset);
      start.setHours(0, 0, 0, 0);
      const end = new Date(start);
      end.setDate(start.getDate() + 7);

      const counts = new Array(7).fill(0);
      const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

      reportsWithDate.forEach(({ date }) => {
        if (date >= start && date < end) {
          const idx = (date.getDay() + 6) % 7; // map Sunday(0) -> 6
          counts[idx] += 1;
        }
      });

      return { labels, data: counts };
    }

    if (range === 'This Month') {
      const start = new Date(now.getFullYear(), now.getMonth(), 1);
      const end = new Date(now.getFullYear(), now.getMonth() + 1, 1);
      const daysInMonth = Math.floor((end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));
      const counts = new Array(daysInMonth).fill(0);
      const labels = counts.map((_, i) => `${i + 1}`);

      reportsWithDate.forEach(({ date }) => {
        if (date >= start && date < end) {
          counts[date.getDate() - 1] += 1;
        }
      });

      return { labels, data: counts };
    }

    // All time: group by YYYY-MM (last 12 months max for readability)
    const grouped = new Map<string, number>();
    reportsWithDate.forEach(({ date }) => {
      const key = `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}`;
      grouped.set(key, (grouped.get(key) ?? 0) + 1);
    });

    const sortedKeys = Array.from(grouped.keys()).sort();
    const last12 = sortedKeys.slice(-12);
    const labels = last12;
    const data = last12.map((k) => grouped.get(k) ?? 0);
    return { labels, data };
  }

  private filterReportsByCategory(reports: ReportRecord[], category: string): ReportRecord[] {
    if (category === 'Total Reports') {
      return reports;
    }

    return reports.filter((report) => {
      const rawType = (report['incidentType'] ?? report['incident_type'] ?? report['type'] ?? '').toString();
      const type = rawType.trim().toLowerCase();

      if (!type) return false;

      switch (category) {
        case 'Fire Emergencies':
          return type.includes('fire');
        case 'Vehicular Emergencies':
          return type.includes('vehic') || type.includes('car') || type.includes('traffic');
        case 'Other Emergencies':
          return type.includes('other');
        case 'Road Obstruction':
          return type.includes('road') || type.includes('obstruction') || type.includes('block');
        case 'Natural Hazards':
          return type.includes('flood') ||
                 type.includes('earthquake') ||
                 type.includes('quake') ||
                 type.includes('storm') ||
                 type.includes('typhoon') ||
                 type.includes('hazard') ||
                 type.includes('landslide');
        default:
          return false;
      }
    });
  }

  private coerceReportDate(report: ReportRecord): { date: Date | null } {
    const candidate = report.reportedAt ?? report.createdAt ?? report.timestamp;
    if (!candidate) return { date: null };

    // Firestore Timestamp has toDate(); JS Date stays as-is
    if (typeof candidate.toDate === 'function') {
      return { date: candidate.toDate() as Date };
    }

    const parsed = new Date(candidate);
    if (!isNaN(parsed.getTime())) {
      return { date: parsed };
    }

    return { date: null };
  }

  async printToPDF() {
    try {
      const pdf = new jsPDF({
        orientation: 'portrait',
        unit: 'mm',
        format: 'a4',
      });

      const pageWidth = pdf.internal.pageSize.getWidth();
      const pageHeight = pdf.internal.pageSize.getHeight();
      const margin = 8;
      const contentWidth = pageWidth - 2 * margin;
      let yPosition = margin;

      // PAGE 1: TITLE AND SUMMARY
      const headerHeight = await this.addPDFHeader(pdf, yPosition);
      yPosition += headerHeight + 6;

      // Summary statistics
      this.addPDFSummary(pdf, yPosition, contentWidth, margin);
      yPosition += 50;

      // Category breakdown
      this.addPDFCategoryBreakdown(pdf, yPosition, contentWidth, margin);

      // DETAILED REPORTS TABLE
      pdf.addPage();
      yPosition = margin;

      this.addPDFReportsTable(pdf, yPosition, contentWidth, margin);

      // Save PDF
      const date = new Date().toISOString().split('T')[0];
      pdf.save(`emergency-report-${date}.pdf`);
    } catch (error) {
      console.error('Error generating PDF:', error);
    }
  }

  private async addPDFHeader(pdf: jsPDF, yPosition: number): Promise<number> {
    const pageWidth = pdf.internal.pageSize.getWidth();
    const headerHeight = 52;

    // Background band
    pdf.setFillColor(172, 27, 34);
    pdf.rect(0, yPosition, pageWidth, headerHeight, 'F');

    const logoTop = yPosition + 8;
    let logoAdded = false;
    try {
      const logoData = await this.loadImageData('assets/images/RESQ-white.png');
      const logoWidth = 70;
      const logoHeight = 22;
      const logoX = (pageWidth - logoWidth) / 2;
      pdf.addImage(logoData, 'PNG', logoX, logoTop, logoWidth, logoHeight);
      logoAdded = true;
    } catch (e) {
      console.warn('Could not load logo for PDF header:', e);
    }

    pdf.setTextColor(255, 255, 255);
    pdf.setFontSize(14);
    pdf.setFont('helvetica', 'bold');
    const titleY = (logoAdded ? logoTop + 24 : yPosition + 16);
    pdf.text('Dashboard Report', pageWidth / 2, titleY, { align: 'center' });

    pdf.setFontSize(10);
    pdf.setFont('helvetica', 'normal');
    const date = new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: '2-digit' });
    const time = new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
    pdf.text(`Generated: ${date} | ${time}`, pageWidth / 2, titleY + 10, { align: 'center' });

    pdf.setTextColor(0, 0, 0);
    return headerHeight;
  }

  private addPDFSummary(pdf: jsPDF, yPosition: number, contentWidth: number, margin: number) {
    pdf.setTextColor(26, 26, 26);
    pdf.setFontSize(12);
    pdf.setFont('helvetica', 'bold');
    pdf.text('EXECUTIVE SUMMARY', margin, yPosition);

    yPosition += 8;
    pdf.setFont('helvetica', 'normal');

    const summaryData = [
      { label: 'Total Reports', value: this.totalReports, color: [172, 27, 34] },
      { label: 'Approved & Resolved', value: this.approvedReports, color: [0, 164, 88] },
      { label: 'Flagged Reports', value: this.flaggedReports, color: [240, 144, 2] },
    ];

    const boxWidth = (contentWidth - 4) / 3;
    summaryData.forEach((item, index) => {
      const x = margin + index * (boxWidth + 2);

      // Draw box background
      pdf.setFillColor(item.color[0], item.color[1], item.color[2]);
      pdf.rect(x, yPosition, boxWidth, 28, 'F');

      // Draw text
      pdf.setTextColor(255, 255, 255);
      pdf.setFontSize(9);
      pdf.setFont('helvetica', 'normal');
      pdf.text(item.label, x + boxWidth / 2, yPosition + 8, { align: 'center' });

      pdf.setFontSize(18);
      pdf.setFont('helvetica', 'bold');
      pdf.text(item.value.toString(), x + boxWidth / 2, yPosition + 20, { align: 'center' });
    });

    pdf.setTextColor(0, 0, 0);
  }

  private addPDFCategoryBreakdown(pdf: jsPDF, yPosition: number, contentWidth: number, margin: number) {
    pdf.setTextColor(26, 26, 26);
    pdf.setFontSize(12);
    pdf.setFont('helvetica', 'bold');
    pdf.text('INCIDENT CATEGORIES', margin, yPosition);

    yPosition += 8;
    pdf.setFontSize(10);
    pdf.setFont('helvetica', 'normal');

    const categories = [
      { label: 'Other Emergencies', value: this.otherEmergencies, color: [0, 164, 88] },
      { label: 'Vehicular Emergencies', value: this.vehicularEmergencies, color: [240, 144, 2] },
      { label: 'Fire Emergencies', value: this.fireEmergencies, color: [172, 27, 34] },
      { label: 'Road Obstruction', value: this.roadObstructions, color: [255, 200, 6] },
      { label: 'Natural Hazards', value: this.naturalHazards, color: [60, 131, 237] },
    ];

    const boxWidth = (contentWidth - 2) / 2;
    categories.forEach((cat, index) => {
      const row = Math.floor(index / 2);
      const col = index % 2;
      const x = margin + col * (boxWidth + 2);
      const y = yPosition + row * 12;

      // Draw colored indicator
      pdf.setFillColor(cat.color[0], cat.color[1], cat.color[2]);
      pdf.rect(x, y + 1, 3, 3, 'F');

      // Draw text
      pdf.setTextColor(26, 26, 26);
      pdf.text(`${cat.label}: `, x + 5, y + 4);
      pdf.setFont('helvetica', 'bold');
      pdf.text(cat.value.toString(), x + boxWidth - 10, y + 4);
      pdf.setFont('helvetica', 'normal');
    });

    pdf.setTextColor(0, 0, 0);
  }

  private async createCategoryChart(category: string, color: string): Promise<HTMLCanvasElement> {
    // Create a temporary container for the chart
    const container = document.createElement('div');
    container.style.display = 'block';
    container.style.width = '600px';
    container.style.height = '300px';
    container.style.position = 'absolute';
    container.style.left = '-9999px';
    container.style.top = '-9999px';
    document.body.appendChild(container);

    const canvas = document.createElement('canvas');
    canvas.width = 600;
    canvas.height = 300;
    container.appendChild(canvas);

    const { labels, data } = this.buildChartData(this.selectedTimeRange, category);

    // Create Chart.js instance
    const Chart = (window as any).Chart;
    if (!Chart) {
      document.body.removeChild(container);
      throw new Error('Chart.js not loaded');
    }

    const ctx = canvas.getContext('2d');
    if (!ctx) {
      document.body.removeChild(container);
      return canvas;
    }

    // Set white background
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    new Chart(ctx, {
      type: 'bar',
      data: {
        labels: labels,
        datasets: [
          {
            label: category,
            data: data,
            backgroundColor: color,
            borderColor: color,
            borderWidth: 1,
            borderRadius: 4,
          },
        ],
      },
      options: {
        responsive: false,
        plugins: {
          legend: {
            display: true,
            position: 'top',
          },
          tooltip: {
            enabled: true,
          },
        },
        scales: {
          x: {
            grid: {
              color: '#e0e0e0',
            },
            ticks: {
              color: '#666',
              font: {
                size: 10,
              },
            },
          },
          y: {
            beginAtZero: true,
            grid: {
              color: '#e0e0e0',
            },
            ticks: {
              color: '#666',
              font: {
                size: 10,
              },
            },
          },
        },
      } as any,
    });

    // Wait for Chart.js to render
    await new Promise(resolve => setTimeout(resolve, 500));

    // Convert to canvas
    const outputCanvas = document.createElement('canvas');
    outputCanvas.width = 600;
    outputCanvas.height = 300;
    const outputCtx = outputCanvas.getContext('2d');
    if (outputCtx) {
      outputCtx.drawImage(canvas, 0, 0);
    }

    // Cleanup
    document.body.removeChild(container);

    return outputCanvas;
  }

  async printGraphToPDF() {
    try {
      const pdf = new jsPDF({
        orientation: 'landscape',
        unit: 'mm',
        format: 'a4',
      });

      const pageWidth = pdf.internal.pageSize.getWidth();
      const pageHeight = pdf.internal.pageSize.getHeight();
      const margin = 15;
      const contentWidth = pageWidth - 2 * margin;
      let yPosition = margin;

      // Header
      pdf.setFillColor(172, 27, 34);
      pdf.rect(0, 0, pageWidth, 45, 'F');

      const logoTop = 8;
      let logoAdded = false;
      try {
        const logoData = await this.loadImageData('assets/images/RESQ-white.png');
        const logoWidth = 50;
        const logoHeight = 20;
        const logoX = (pageWidth - logoWidth) / 2;
        pdf.addImage(logoData, 'PNG', logoX, logoTop, logoWidth, logoHeight);
        logoAdded = true;
      } catch (e) {
        console.warn('Could not load logo for graph PDF:', e);
      }

      pdf.setTextColor(255, 255, 255);
      pdf.setFontSize(14);
      pdf.setFont('helvetica', 'bold');
      const titleY = logoAdded ? logoTop + 22 : 18;
      pdf.text('Analytics Report', pageWidth / 2, titleY, { align: 'center' });

      pdf.setFontSize(9);
      pdf.setFont('helvetica', 'normal');
      const date = new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: '2-digit' });
      const time = new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
      pdf.text(`Generated: ${date} | ${time}`, pageWidth / 2, titleY + 8, { align: 'center' });

      yPosition = 55;
      pdf.setTextColor(26, 26, 26);

      // Chart info
      pdf.setFontSize(12);
      pdf.setFont('helvetica', 'bold');
      pdf.text('ANALYTICS & TRENDS', margin, yPosition);
      yPosition += 10;

      pdf.setFontSize(10);
      pdf.setFont('helvetica', 'normal');
      pdf.text(`Category: ${this.selectedCategory}`, margin, yPosition);
      yPosition += 6;
      pdf.text(`Time Range: ${this.selectedTimeRange}`, margin, yPosition);
      yPosition += 12;

      // Capture chart
      try {
        const chartElement = document.querySelector('.reports-card canvas') as HTMLCanvasElement;
        if (chartElement) {
          const chartCanvas = await html2canvas(chartElement, {
            scale: 2,
            backgroundColor: '#ffffff',
            logging: false,
            useCORS: true,
            allowTaint: true,
          });
          const chartImg = chartCanvas.toDataURL('image/png');
          const maxChartHeight = pageHeight - yPosition - 15;
          const chartHeight = Math.min((chartCanvas.height * contentWidth) / chartCanvas.width, maxChartHeight);
          pdf.addImage(chartImg, 'PNG', margin, yPosition, contentWidth, chartHeight);
        } else {
          pdf.text('Chart not available', margin, yPosition);
        }
      } catch (e) {
        console.error('Could not capture chart:', e);
        pdf.text('Error capturing chart', margin, yPosition);
      }

      // Save
      const dateStr = new Date().toISOString().split('T')[0];
      pdf.save(`analytics-report-${dateStr}.pdf`);
    } catch (error) {
      console.error('Error generating graph PDF:', error);
    }
  }

  private async loadImageData(url: string): Promise<string> {
    const resp = await fetch(url);
    if (!resp.ok) {
      throw new Error(`Failed to load image: ${resp.status}`);
    }
    const blob = await resp.blob();

    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onerror = () => reject(new Error('Failed to read image blob'));
      reader.onload = () => resolve(reader.result as string);
      reader.readAsDataURL(blob);
    });
  }

  private addPDFReportsTable(pdf: jsPDF, yPosition: number, contentWidth: number, margin: number) {
    pdf.setTextColor(26, 26, 26);
    pdf.setFontSize(12);
    pdf.setFont('helvetica', 'bold');
    pdf.text('DETAILED REPORTS', margin, yPosition);

    yPosition += 10;

    // Table headers
    const headers = ['Type', 'Status', 'Date', 'Description'];
    const columnWidths = [contentWidth * 0.28, contentWidth * 0.18, contentWidth * 0.14, contentWidth * 0.40];

    pdf.setFontSize(10);
    pdf.setFont('helvetica', 'bold');
    pdf.setFillColor(26, 26, 26);
    pdf.setTextColor(255, 255, 255);

    // Single header bar spanning all columns
    pdf.rect(margin, yPosition, contentWidth, 10, 'F');

    let xOffset = margin;
    headers.forEach((header, index) => {
      pdf.text(header, xOffset + columnWidths[index] / 8, yPosition + 6,);
      xOffset += columnWidths[index];
    });

    yPosition += 14;
    pdf.setFont('helvetica', 'normal');
    pdf.setTextColor(26, 26, 26);
    pdf.setFontSize(8);

    let rowCount = 0;
    // Table rows
    this.allReports.slice(0, 50).forEach((report) => {
      if (yPosition > pdf.internal.pageSize.getHeight() - 15) {
        pdf.addPage();
        yPosition = margin;
        
        // Redraw headers
        pdf.setFont('helvetica', 'bold');
        pdf.setFillColor(26, 26, 26);
        pdf.setTextColor(255, 255, 255);
        pdf.setFontSize(10);
        // Single header bar spanning all columns
        pdf.rect(margin, yPosition, contentWidth, 14, 'F');

        xOffset = margin;
        headers.forEach((header, index) => {
          pdf.text(header, xOffset + columnWidths[index] / 2, yPosition + 9, { align: 'center' });
          xOffset += columnWidths[index];
        });
        yPosition += 14;
        pdf.setFont('helvetica', 'normal');
        pdf.setTextColor(26, 26, 26);
      }

      const typeRaw = (report['incidentType'] ?? report['incident_type'] ?? report['type'] ?? 'N/A').toString();
      const statusRaw = (report['status'] ?? 'N/A').toString();
      const descriptionRaw = (report['description'] ?? 'N/A').toString();

      // Safe date parsing
      let reportDate = 'N/A';
      if (report['reportedAt']) {
        try {
          const dateObj = typeof report['reportedAt'].toDate === 'function'
            ? report['reportedAt'].toDate()
            : new Date(report['reportedAt']);
          if (!isNaN(dateObj.getTime())) {
            reportDate = dateObj.toLocaleDateString('en-US', { month: '2-digit', day: '2-digit', year: '2-digit' });
          }
        } catch (e) {
          reportDate = 'Invalid';
        }
      }

      const typeLines = pdf.splitTextToSize(typeRaw, columnWidths[0] - 2);
      const statusLines = pdf.splitTextToSize(statusRaw, columnWidths[1] - 2);
      const dateLines = pdf.splitTextToSize(reportDate, columnWidths[2] - 2);
      const descLines = pdf.splitTextToSize(descriptionRaw, columnWidths[3] - 2);

      const maxLines = Math.max(typeLines.length, statusLines.length, dateLines.length, descLines.length);
      const rowHeight = Math.max(7, maxLines * 4 + 2);

      // Page break check with upcoming row
      if (yPosition + rowHeight > pdf.internal.pageSize.getHeight() - 10) {
        pdf.addPage();
        yPosition = margin;

        // Redraw headers on new page
        pdf.setFont('helvetica', 'bold');
        pdf.setFillColor(26, 26, 26);
        pdf.setTextColor(255, 255, 255);
        pdf.setFontSize(10);
        // Single header bar spanning all columns
        pdf.rect(margin, yPosition, contentWidth, 14, 'F');

        xOffset = margin;
        headers.forEach((header, index) => {
          pdf.text(header, xOffset + columnWidths[index] / 2, yPosition + 9, { align: 'center' });
          xOffset += columnWidths[index];
        });
        yPosition += 14;
        pdf.setFont('helvetica', 'normal');
        pdf.setTextColor(26, 26, 26);
      }

      // Alternate row colors
      if (rowCount % 2 === 0) {
        pdf.setFillColor(245, 245, 245);
        xOffset = margin;
        for (let i = 0; i < columnWidths.length; i++) {
          pdf.rect(xOffset, yPosition - 4, columnWidths[i], rowHeight, 'F');
          xOffset += columnWidths[i];
        }
      }

      xOffset = margin;
      typeLines.forEach((line: string, idx: number) => pdf.text(line, xOffset + 1, yPosition + 4 * idx));
      xOffset += columnWidths[0];
      statusLines.forEach((line: string, idx: number) => pdf.text(line, xOffset + 1, yPosition + 4 * idx));
      xOffset += columnWidths[1];
      dateLines.forEach((line: string, idx: number) => pdf.text(line, xOffset + 1, yPosition + 4 * idx));
      xOffset += columnWidths[2];
      descLines.forEach((line: string, idx: number) => pdf.text(line, xOffset + 1, yPosition + 4 * idx));

      yPosition += rowHeight;
      rowCount++;
    });

    // Footer
    yPosition += 5;
    pdf.setTextColor(100, 100, 100);
    pdf.setFontSize(8);
    pdf.text(`Total Reports Shown: ${Math.min(50, this.allReports.length)} of ${this.allReports.length}`, margin, yPosition);
  }
}

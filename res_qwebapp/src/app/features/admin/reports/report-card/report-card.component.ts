import { ChangeDetectionStrategy, Component, EventEmitter, Input, Output } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Comment, Report } from '../reports.models';

@Component({
  selector: 'app-report-card',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './report-card.component.html',
  styleUrls: ['./report-card.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ReportCardComponent {
  @Input({ required: true }) report!: Report;
  @Input() isExpanded = false;
  @Input() commentsLoading = false;
  @Input() visibleComments: Comment[] = [];
  @Input() totalComments = 0;
  @Input() hasMoreComments = false;
  @Input() loadingMoreComments = false;

  @Output() toggleCommentsClicked = new EventEmitter<Report>();
  @Output() approveClicked = new EventEmitter<Report>();
  @Output() rejectClicked = new EventEmitter<Report>();
  @Output() revertClicked = new EventEmitter<Report>();
  @Output() showMoreCommentsClicked = new EventEmitter<string>();

  trackByCommentId(index: number, comment: Comment): string {
    return comment.id || `comment-${comment.reportId}-${index}`;
  }

  onToggleComments(): void {
    this.toggleCommentsClicked.emit(this.report);
  }

  onApprove(): void {
    this.approveClicked.emit(this.report);
  }

  onReject(): void {
    this.rejectClicked.emit(this.report);
  }

  onRevert(): void {
    this.revertClicked.emit(this.report);
  }

  onShowMoreComments(): void {
    this.showMoreCommentsClicked.emit(this.report.id);
  }

  onImageError(event: Event): void {
    const image = event.target as HTMLImageElement | null;
    if (!image) return;

    const fallbackSrc = image.getAttribute('data-fallback-src') || '';
    if (fallbackSrc && image.src !== fallbackSrc) {
      image.src = fallbackSrc;
      return;
    }

    if (image.src.endsWith('/assets/images/placeholder-report.jpg')) {
      return;
    }
    image.src = 'assets/images/placeholder-report.jpg';
  }
}

export type FilterType = 'pending' | 'approved' | 'flagged';
export type DateFilterType = 'all' | 'today' | 'week' | 'month' | 'year';
export type IncidentFilterType = 'all' | 'fire' | 'flood' | 'vehicular' | 'earthquake' | 'other';

export interface Report {
  id: string;
  title: string;
  category: string;
  categoryKey: string;
  incidentFilterKey: Exclude<IncidentFilterType, 'all'>;
  location: string;
  date: string;
  time: string;
  reporter: string;
  description: string;
  image: string;
  imageThumb?: string;
  imageThumbWebp?: string;
  greenFlags?: number;
  redFlags?: number;
  comments?: number;
  status: 'Pending' | 'Approved' | 'Flagged';
  incidentStatus?: string;
  sortTimestamp?: number;
  approvedBy?: string;
  approvedAt?: string;
  respondingAt?: string;
  respondingBy?: string;
  arrivedAt?: string;
  arrivedBy?: string;
  resolvedAt?: string;
  resolvedBy?: string;
  flaggedAt?: string;
  flaggedBy?: string;
  activityResponderDisplay: string;
  timeRespondingDisplay: string;
  timeOnSceneDisplay: string;
  finalActivityLabelDisplay: string;
  finalActivityTimeDisplay: string;
}

export interface Comment {
  id: string;
  text: string;
  author: string;
  timestamp: Date;
  displayTime: string;
  greenFlags: number;
  redFlags: number;
  reportId: string;
  reportTitle: string;
  reportStatus: string;
}

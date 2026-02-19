/**
 * Command Center - Frontend Types
 * These mirror the Python Pydantic models exactly.
 */

export type Source = 'gmail' | 'outlook' | 'slack' | 'asana' | 'plane';
export type NotificationType = 'email' | 'message' | 'task_update' | 'task_assigned' | 'mention' | 'comment' | 'reminder';
export type Priority = 'urgent' | 'high' | 'normal' | 'low';
export type TriageStatus = 'unread' | 'read' | 'snoozed' | 'archived' | 'actioned';

export interface Notification {
  id: string;
  source: Source;
  source_account: string;
  source_id: string;
  notification_type: NotificationType;
  title: string;
  body: string;
  sender_name: string;
  sender_avatar?: string;
  timestamp: string;
  priority: Priority;
  triage_status: TriageStatus;
  is_actionable: boolean;
  thread_id?: string;
  channel_name?: string;
  project_name?: string;
  snoozed_until?: string;
  raw_payload?: Record<string, any>;
}

export interface WebSocketMessage {
  event: 'new_notification' | 'notification_updated' | 'notification_removed' | 'connection_status' | 'error' | 'initial_load';
  data: any;
}

export interface ServiceStatus {
  service: string;
  connected: boolean;
  account: string;
}

export interface TaskCreate {
  title: string;
  description?: string;
  target: 'plane' | 'asana';
  priority?: Priority;
  project_id?: string;
  source_notification_id?: string;
}

// Source metadata for display
export const SOURCE_CONFIG: Record<Source, { label: string; color: string; icon: string }> = {
  gmail: { label: 'Gmail', color: '#EA4335', icon: '✉️' },
  outlook: { label: 'Outlook', color: '#0078D4', icon: '📧' },
  slack: { label: 'Slack', color: '#4A154B', icon: '💬' },
  asana: { label: 'Asana', color: '#F06A6A', icon: '📋' },
  plane: { label: 'Plane', color: '#3F76FF', icon: '✈️' },
};

export const PRIORITY_CONFIG: Record<Priority, { label: string; color: string }> = {
  urgent: { label: 'Urgent', color: '#EF4444' },
  high: { label: 'High', color: '#F97316' },
  normal: { label: 'Normal', color: '#6B7280' },
  low: { label: 'Low', color: '#9CA3AF' },
};

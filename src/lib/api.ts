/**
 * Command Center - API Client
 * Handles REST calls to the Python backend for actions.
 */

import type { TaskCreate } from '$lib/types';

const BASE_URL = 'http://127.0.0.1:8766/api';

async function apiCall(path: string, options: RequestInit = {}) {
  const resp = await fetch(`${BASE_URL}${path}`, {
    headers: { 'Content-Type': 'application/json', ...options.headers as any },
    ...options,
  });
  if (!resp.ok) {
    const err = await resp.json().catch(() => ({ detail: resp.statusText }));
    throw new Error(err.detail || 'API request failed');
  }
  return resp.json();
}

export const api = {
  /** Reply to a notification (email or Slack message) */
  async reply(notificationId: string, body: string, source: string, sourceAccount: string, sourceId: string) {
    return apiCall(`/notifications/${notificationId}/action`, {
      method: 'POST',
      body: JSON.stringify({
        notification_id: notificationId,
        action: 'reply',
        payload: { body, source, source_account: sourceAccount, source_id: sourceId },
      }),
    });
  },

  /** Archive a notification */
  async archive(notificationId: string) {
    return apiCall(`/notifications/${notificationId}/action`, {
      method: 'POST',
      body: JSON.stringify({ notification_id: notificationId, action: 'archive' }),
    });
  },

  /** Mark a notification as read */
  async markRead(notificationId: string) {
    return apiCall(`/notifications/${notificationId}/action`, {
      method: 'POST',
      body: JSON.stringify({ notification_id: notificationId, action: 'mark_read' }),
    });
  },

  /** Snooze a notification */
  async snooze(notificationId: string, minutes: number = 30) {
    return apiCall(`/notifications/${notificationId}/action`, {
      method: 'POST',
      body: JSON.stringify({
        notification_id: notificationId,
        action: 'snooze',
        payload: { snooze_minutes: minutes },
      }),
    });
  },

  /** Create a task in Plane or Asana */
  async createTask(task: TaskCreate) {
    return apiCall('/tasks', {
      method: 'POST',
      body: JSON.stringify(task),
    });
  },

  /** Get service statuses */
  async getServiceStatus() {
    return apiCall('/services/status');
  },

  /** Health check */
  async health() {
    return apiCall('/health');
  },

  /** Get OAuth auth status for Gmail accounts */
  async getAuthStatus() {
    return apiCall('/auth/status');
  },
};

/**
 * Command Center - Svelte Stores
 *
 * Think of stores like a shared whiteboard: any component can read from it
 * or write to it, and everyone sees the updates instantly.
 */

import { writable, derived } from 'svelte/store';
import type { Notification, ServiceStatus, Source, TriageStatus } from '$lib/types';

// ============================================================
// Notifications Store
// ============================================================

function createNotificationStore() {
  const { subscribe, set, update } = writable<Notification[]>([]);

  return {
    subscribe,
    set,

    /** Add a new notification (or update if it already exists) */
    addOrUpdate(notification: Notification) {
      update(items => {
        const idx = items.findIndex(n =>
            n.id === notification.id ||
            (n.source === notification.source && n.source_id === notification.source_id)
        );
        if (idx >= 0) {
          items[idx] = { ...items[idx], ...notification };
          return [...items];
        }
        return [notification, ...items];
      });
    },

    /** Bulk load (initial load from WebSocket) */
    loadMany(notifications: Notification[]) {
      set(notifications);
    },

    /** Update a notification's properties */
    updateOne(id: string, updates: Partial<Notification>) {
      update(items =>
        items.map(n => (n.id === id ? { ...n, ...updates } : n))
      );
    },

    /** Remove a notification */
    remove(id: string) {
      update(items => items.filter(n => n.id !== id));
    },

    /** Archive a notification */
    archive(id: string) {
      update(items =>
        items.map(n => (n.id === id ? { ...n, triage_status: 'archived' as TriageStatus } : n))
      );
    },

    /** Mark as read */
    markRead(id: string) {
      update(items =>
        items.map(n => (n.id === id ? { ...n, triage_status: 'read' as TriageStatus } : n))
      );
    },
  };
}

export const notifications = createNotificationStore();

// ============================================================
// Derived Stores (filtered views)
// ============================================================

/** Only unread notifications */
export const unreadNotifications = derived(notifications, $n =>
  $n.filter(n => n.triage_status === 'unread')
);

/** Notifications grouped by source */
export const notificationsBySource = derived(notifications, $n => {
  const groups: Record<string, Notification[]> = {};
  for (const notif of $n) {
    const key = notif.source;
    if (!groups[key]) groups[key] = [];
    groups[key].push(notif);
  }
  return groups;
});

/** Count of unread by source (for sidebar badges) */
export const unreadCounts = derived(notifications, $n => {
  const counts: Record<string, number> = { gmail: 0, outlook: 0, slack: 0, asana: 0, plane: 0, total: 0 };
  for (const notif of $n) {
    if (notif.triage_status === 'unread') {
      counts[notif.source] = (counts[notif.source] || 0) + 1;
      counts.total++;
    }
  }
  return counts;
});

// ============================================================
// UI State
// ============================================================

/** Currently selected notification (for detail panel) */
export const selectedNotification = writable<Notification | null>(null);

/** Active filter */
export const activeFilter = writable<Source | 'all'>('all');

/** Search query */
export const searchQuery = writable('');

/** Service connection statuses */
export const serviceStatuses = writable<ServiceStatus[]>([]);

/** Is the task creator modal open? */
export const showTaskCreator = writable(false);

/** Backend connection state: 'waiting' | 'ready' | 'error' */
export const backendStatus = writable<'waiting' | 'ready' | 'error'>('waiting');

/** Is the settings panel open? */
export const showSettings = writable(false);

/** Filtered notifications based on active filter and search */
export const filteredNotifications = derived(
  [notifications, activeFilter, searchQuery],
  ([$notifications, $filter, $search]) => {
    let result = $notifications.filter(n => n.triage_status !== 'archived');

    if ($filter !== 'all') {
      result = result.filter(n => n.source === $filter);
    }

    if ($search.trim()) {
      const q = $search.toLowerCase();
      result = result.filter(
        n =>
          n.title.toLowerCase().includes(q) ||
          n.body.toLowerCase().includes(q) ||
          n.sender_name.toLowerCase().includes(q)
      );
    }

    // Sort: urgent first, then by timestamp
    result.sort((a, b) => {
      const priorityOrder = { urgent: 0, high: 1, normal: 2, low: 3 };
      const pDiff = priorityOrder[a.priority] - priorityOrder[b.priority];
      if (pDiff !== 0) return pDiff;
      return new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime();
    });

    return result;
  }
);

/**
 * Command Center - WebSocket Client
 *
 * This is the pipe between the Python backend and the Svelte frontend.
 * It auto-reconnects if the connection drops (like your phone automatically
 * reconnecting to WiFi).
 */

import {
  isPermissionGranted,
  requestPermission,
  sendNotification,
} from '@tauri-apps/plugin-notification';
import { notifications, serviceStatuses, backendStatus } from '$lib/stores';
import type { WebSocketMessage, Notification, ServiceStatus } from '$lib/types';

const BACKEND_URL = 'http://127.0.0.1:8766';
const WS_URL = 'ws://127.0.0.1:8766/ws';
const RECONNECT_DELAY = 3000;
const MAX_RECONNECT_DELAY = 30000;
const HEALTH_POLL_INTERVAL = 500;
const HEALTH_TIMEOUT = 30000;

let ws: WebSocket | null = null;
let reconnectAttempts = 0;
let reconnectTimeout: ReturnType<typeof setTimeout> | null = null;
let notificationsPermitted = false;

export const wsState = {
  connected: false,
};

/**
 * Request notification permissions from the OS.
 */
async function initDesktopNotifications() {
  try {
    notificationsPermitted = await isPermissionGranted();
    if (!notificationsPermitted) {
      const permission = await requestPermission();
      notificationsPermitted = permission === 'granted';
    }
  } catch {
    // Not running in Tauri (e.g., browser dev mode)
    notificationsPermitted = false;
  }
}

/**
 * Send a native desktop notification for high-priority items.
 * Only fires when the app window is not focused.
 */
function maybeDesktopNotify(notif: Notification) {
  if (!notificationsPermitted) return;
  if (document.hasFocus()) return;
  if (notif.priority !== 'urgent' && notif.priority !== 'high') return;

  try {
    sendNotification({
      title: `${notif.source.toUpperCase()}: ${notif.sender_name}`,
      body: notif.title,
    });
  } catch {
    // Silently fail if not in Tauri
  }
}

/**
 * Wait for the backend to become available by polling /api/health.
 * Resolves when the backend is ready, rejects after timeout.
 */
export function waitForBackend(): Promise<void> {
  backendStatus.set('waiting');

  return new Promise((resolve, reject) => {
    const startTime = Date.now();

    const poll = async () => {
      try {
        const resp = await fetch(`${BACKEND_URL}/api/health`);
        if (resp.ok) {
          backendStatus.set('ready');
          initDesktopNotifications();
          resolve();
          return;
        }
      } catch {
        // Backend not ready yet, keep polling
      }

      if (Date.now() - startTime > HEALTH_TIMEOUT) {
        backendStatus.set('error');
        reject(new Error('Backend did not become ready within timeout'));
        return;
      }

      setTimeout(poll, HEALTH_POLL_INTERVAL);
    };

    poll();
  });
}

/**
 * Connect to the backend WebSocket.
 */
export function connectWebSocket() {
  if (ws?.readyState === WebSocket.OPEN) return;

  try {
    ws = new WebSocket(WS_URL);

    ws.onopen = () => {
      console.log('[WS] Connected to backend');
      wsState.connected = true;
      reconnectAttempts = 0;
    };

    ws.onmessage = (event) => {
      try {
        const message: WebSocketMessage = JSON.parse(event.data);
        handleMessage(message);
      } catch (e) {
        console.error('[WS] Failed to parse message:', e);
      }
    };

    ws.onclose = () => {
      console.log('[WS] Disconnected');
      wsState.connected = false;
      scheduleReconnect();
    };

    ws.onerror = (error) => {
      console.error('[WS] Error:', error);
      ws?.close();
    };
  } catch (e) {
    console.error('[WS] Connection failed:', e);
    scheduleReconnect();
  }
}

/**
 * Schedule a reconnection with exponential backoff.
 */
function scheduleReconnect() {
  if (reconnectTimeout) clearTimeout(reconnectTimeout);

  const delay = Math.min(
    RECONNECT_DELAY * Math.pow(1.5, reconnectAttempts),
    MAX_RECONNECT_DELAY
  );

  console.log(`[WS] Reconnecting in ${Math.round(delay / 1000)}s...`);
  reconnectTimeout = setTimeout(() => {
    reconnectAttempts++;
    connectWebSocket();
  }, delay);
}

/**
 * Handle incoming WebSocket messages.
 */
function handleMessage(message: WebSocketMessage) {
  switch (message.event) {
    case 'initial_load': {
      const items = message.data.notifications as Notification[];
      notifications.loadMany(items);
      console.log(`[WS] Loaded ${items.length} notifications`);
      break;
    }

    case 'new_notification': {
      const notif = message.data as Notification;
      notifications.addOrUpdate(notif);
      maybeDesktopNotify(notif);
      break;
    }

    case 'notification_updated': {
      const { id, ...updates } = message.data;
      notifications.updateOne(id, updates);
      break;
    }

    case 'notification_removed': {
      notifications.remove(message.data.id);
      break;
    }

    case 'connection_status': {
      const status = message.data as ServiceStatus;
      serviceStatuses.update(statuses => {
        const idx = statuses.findIndex(
          s => s.service === status.service && s.account === status.account
        );
        if (idx >= 0) {
          statuses[idx] = status;
          return [...statuses];
        }
        return [...statuses, status];
      });
      break;
    }

    case 'error': {
      console.error('[WS] Backend error:', message.data);
      break;
    }
  }
}

/**
 * Send a message to the backend via WebSocket.
 */
export function sendMessage(data: any) {
  if (ws?.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(data));
  } else {
    console.warn('[WS] Cannot send - not connected');
  }
}

/**
 * Disconnect cleanly.
 */
export function disconnectWebSocket() {
  if (reconnectTimeout) clearTimeout(reconnectTimeout);
  ws?.close();
  ws = null;
}

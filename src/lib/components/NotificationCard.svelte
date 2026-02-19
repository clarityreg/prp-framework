<!--
  Command Center - Notification Card
  Displays a single notification in the feed.
  Click to expand, hover for quick actions.
-->
<script>
  import { selectedNotification, notifications } from '$lib/stores';
  import { SOURCE_CONFIG, PRIORITY_CONFIG } from '$lib/types';
  import { api } from '$lib/api';

  export let notification;

  $: config = SOURCE_CONFIG[notification.source];
  $: priorityConfig = PRIORITY_CONFIG[notification.priority];
  $: isSelected = $selectedNotification?.id === notification.id;
  $: isUnread = notification.triage_status === 'unread';
  $: timeAgo = formatTimeAgo(notification.timestamp);

  function select() {
    selectedNotification.set(notification);
    if (isUnread) {
      notifications.markRead(notification.id);
      api.markRead(notification.id).catch(console.error);
    }
  }

  async function quickArchive(e) {
    e.stopPropagation();
    notifications.archive(notification.id);
    if ($selectedNotification?.id === notification.id) {
      selectedNotification.set(null);
    }
    await api.archive(notification.id).catch(console.error);
  }

  function formatTimeAgo(timestamp) {
    const now = new Date();
    const date = new Date(timestamp);
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);

    if (diffMins < 1) return 'now';
    if (diffMins < 60) return `${diffMins}m`;
    const diffHours = Math.floor(diffMins / 60);
    if (diffHours < 24) return `${diffHours}h`;
    const diffDays = Math.floor(diffHours / 24);
    if (diffDays < 7) return `${diffDays}d`;
    return date.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
  }
</script>

<div
  class="card"
  class:selected={isSelected}
  class:unread={isUnread}
  on:click={select}
  on:keydown={(e) => e.key === 'Enter' && select()}
  role="button"
  tabindex="0"
>
  <!-- Source indicator bar -->
  <div class="source-bar" style="background: {config.color}"></div>

  <div class="card-content">
    <div class="card-header">
      <span class="source-tag" style="color: {config.color}">
        {config.icon} {notification.source_account}
      </span>
      <span class="time">{timeAgo}</span>
    </div>

    <div class="card-title">
      {#if notification.priority === 'urgent' || notification.priority === 'high'}
        <span class="priority-dot" style="background: {priorityConfig.color}"></span>
      {/if}
      {notification.title}
    </div>

    <div class="card-body">
      <span class="sender">{notification.sender_name}</span>
      {#if notification.body}
        <span class="separator">—</span>
        <span class="preview">{notification.body.slice(0, 120)}</span>
      {/if}
    </div>

    {#if notification.channel_name || notification.project_name}
      <div class="card-meta">
        {#if notification.channel_name}
          <span class="meta-tag">#{notification.channel_name}</span>
        {/if}
        {#if notification.project_name}
          <span class="meta-tag">📁 {notification.project_name}</span>
        {/if}
      </div>
    {/if}
  </div>

  <!-- Quick actions on hover -->
  <div class="quick-actions">
    <button class="quick-btn" on:click={quickArchive} title="Archive">
      ✓
    </button>
  </div>
</div>

<style>
  .card {
    display: flex;
    position: relative;
    width: 100%;
    text-align: left;
    background: transparent;
    border: none;
    border-bottom: 1px solid var(--border);
    color: var(--text-secondary);
    cursor: pointer;
    transition: background 0.12s ease;
    font-family: 'Outfit', sans-serif;
    padding: 0;
  }

  .card:hover {
    background: var(--bg-hover);
  }

  .card.selected {
    background: var(--bg-active);
  }

  .card.unread {
    color: var(--text-primary);
  }

  .card.unread .card-title {
    font-weight: 600;
  }

  .source-bar {
    width: 3px;
    min-height: 100%;
    flex-shrink: 0;
    opacity: 0.7;
  }

  .card-content {
    flex: 1;
    padding: 12px 16px;
    min-width: 0;
    overflow: hidden;
  }

  .card-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 4px;
  }

  .source-tag {
    font-size: 11px;
    font-weight: 500;
    font-family: var(--mono);
  }

  .time {
    font-size: 11px;
    color: var(--text-muted);
    font-family: var(--mono);
    flex-shrink: 0;
  }

  .card-title {
    font-size: 13px;
    font-weight: 400;
    line-height: 1.4;
    margin-bottom: 4px;
    display: flex;
    align-items: center;
    gap: 6px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .priority-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .card-body {
    font-size: 12px;
    color: var(--text-muted);
    line-height: 1.4;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .sender {
    color: var(--text-secondary);
    font-weight: 500;
  }

  .separator {
    margin: 0 4px;
    opacity: 0.5;
  }

  .card-meta {
    display: flex;
    gap: 8px;
    margin-top: 6px;
  }

  .meta-tag {
    font-size: 10px;
    color: var(--text-muted);
    background: var(--bg-tertiary);
    padding: 2px 6px;
    border-radius: 4px;
    font-family: var(--mono);
  }

  .quick-actions {
    position: absolute;
    right: 12px;
    top: 50%;
    transform: translateY(-50%);
    display: flex;
    gap: 4px;
    opacity: 0;
    transition: opacity 0.15s;
  }

  .card:hover .quick-actions {
    opacity: 1;
  }

  .quick-btn {
    width: 28px;
    height: 28px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-light);
    background: var(--bg-secondary);
    color: var(--text-secondary);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 12px;
    transition: all 0.12s;
  }

  .quick-btn:hover {
    background: var(--accent);
    color: white;
    border-color: var(--accent);
  }
</style>

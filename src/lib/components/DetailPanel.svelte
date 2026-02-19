<!--
  Command Center - Detail Panel
  Shows the full notification content with reply and action buttons.
-->
<script>
  import { selectedNotification, notifications, showTaskCreator } from '$lib/stores';
  import { SOURCE_CONFIG, PRIORITY_CONFIG } from '$lib/types';
  import { api } from '$lib/api';

  let replyText = '';
  let isReplying = false;
  let showSnoozeMenu = false;

  $: notif = $selectedNotification;
  $: config = notif ? SOURCE_CONFIG[notif.source] : null;
  $: canReply = notif && (notif.source === 'gmail' || notif.source === 'outlook');

  function close() {
    selectedNotification.set(null);
  }

  async function handleReply() {
    if (!notif || !replyText.trim()) return;
    isReplying = true;
    try {
      await api.reply(notif.id, replyText, notif.source, notif.source_account, notif.source_id);
      replyText = '';
      notifications.updateOne(notif.id, { triage_status: 'actioned' });
    } catch (e) {
      console.error('Reply failed:', e);
    }
    isReplying = false;
  }

  async function archive() {
    if (!notif) return;
    notifications.archive(notif.id);
    await api.archive(notif.id).catch(console.error);
    close();
  }

  async function snooze(minutes) {
    if (!notif) return;
    notifications.updateOne(notif.id, { triage_status: 'snoozed' });
    await api.snooze(notif.id, minutes).catch(console.error);
    showSnoozeMenu = false;
    close();
  }

  function createTaskFromThis() {
    showTaskCreator.set(true);
  }

  function formatDate(timestamp) {
    return new Date(timestamp).toLocaleString('en-GB', {
      weekday: 'short', day: 'numeric', month: 'short',
      hour: '2-digit', minute: '2-digit',
    });
  }

  function handleKeydown(e) {
    if (e.key === 'Escape') close();
  }
</script>

<svelte:window on:keydown={handleKeydown} />

{#if notif}
  <div class="detail-panel">
    <div class="detail-header">
      <div class="header-left">
        <span class="source-badge" style="background: {config.color}">{config.icon} {config.label}</span>
        <span class="account-label">{notif.source_account}</span>
      </div>
      <button class="close-btn" on:click={close}>✕</button>
    </div>

    <div class="detail-content">
      <h2 class="detail-title">{notif.title}</h2>

      <div class="detail-meta">
        <span class="meta-sender">{notif.sender_name}</span>
        <span class="meta-time">{formatDate(notif.timestamp)}</span>
        {#if notif.priority !== 'normal'}
          <span class="meta-priority" style="color: {PRIORITY_CONFIG[notif.priority].color}">
            ● {PRIORITY_CONFIG[notif.priority].label}
          </span>
        {/if}
      </div>

      {#if notif.channel_name}
        <div class="detail-channel">#{notif.channel_name}</div>
      {/if}
      {#if notif.project_name}
        <div class="detail-channel">📁 {notif.project_name}</div>
      {/if}

      <div class="detail-body">
        {notif.body || 'No content'}
      </div>
    </div>

    <!-- Action Bar -->
    <div class="action-bar">
      <div class="action-buttons">
        <button class="action-btn" on:click={archive} title="Archive">
          <span>✓</span> Archive
        </button>
        <div class="snooze-wrapper">
          <button class="action-btn" on:click={() => showSnoozeMenu = !showSnoozeMenu}>
            <span>⏰</span> Snooze
          </button>
          {#if showSnoozeMenu}
            <div class="snooze-menu">
              <button on:click={() => snooze(30)}>30 min</button>
              <button on:click={() => snooze(60)}>1 hour</button>
              <button on:click={() => snooze(240)}>4 hours</button>
              <button on:click={() => snooze(1440)}>Tomorrow</button>
            </div>
          {/if}
        </div>
        <button class="action-btn" on:click={createTaskFromThis}>
          <span>📋</span> Create Task
        </button>
      </div>
    </div>

    <!-- Reply Section -->
    {#if canReply}
      <div class="reply-section">
        <textarea
          bind:value={replyText}
          placeholder="Write a reply..."
          rows="3"
          on:keydown={(e) => { if (e.metaKey && e.key === 'Enter') handleReply(); }}
        ></textarea>
        <div class="reply-footer">
          <span class="reply-hint">⌘ + Enter to send</span>
          <button
            class="send-btn"
            disabled={!replyText.trim() || isReplying}
            on:click={handleReply}
          >
            {isReplying ? 'Sending...' : 'Send Reply'}
          </button>
        </div>
      </div>
    {/if}
  </div>
{:else}
  <div class="empty-detail">
    <div class="empty-icon">📬</div>
    <p>Select a notification to see details</p>
    <p class="empty-hint">Use ↑↓ arrow keys to navigate</p>
  </div>
{/if}

<style>
  .detail-panel {
    flex: 1;
    display: flex;
    flex-direction: column;
    background: var(--bg-secondary);
    border-left: 1px solid var(--border);
    overflow: hidden;
  }

  .detail-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 16px 20px;
    border-bottom: 1px solid var(--border);
  }

  .header-left {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .source-badge {
    font-size: 11px;
    font-weight: 600;
    color: white;
    padding: 3px 10px;
    border-radius: 12px;
  }

  .account-label {
    font-size: 12px;
    color: var(--text-muted);
    font-family: var(--mono);
  }

  .close-btn {
    width: 28px;
    height: 28px;
    border: none;
    background: transparent;
    color: var(--text-muted);
    cursor: pointer;
    border-radius: var(--radius-sm);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 14px;
    transition: all 0.12s;
  }

  .close-btn:hover {
    background: var(--bg-hover);
    color: var(--text-primary);
  }

  .detail-content {
    flex: 1;
    padding: 24px 20px;
    overflow-y: auto;
  }

  .detail-title {
    font-size: 18px;
    font-weight: 600;
    color: var(--text-primary);
    line-height: 1.4;
    margin-bottom: 12px;
  }

  .detail-meta {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-bottom: 16px;
    flex-wrap: wrap;
  }

  .meta-sender {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-secondary);
  }

  .meta-time {
    font-size: 12px;
    color: var(--text-muted);
    font-family: var(--mono);
  }

  .meta-priority {
    font-size: 11px;
    font-weight: 600;
  }

  .detail-channel {
    font-size: 12px;
    color: var(--text-muted);
    margin-bottom: 8px;
    font-family: var(--mono);
  }

  .detail-body {
    font-size: 14px;
    line-height: 1.7;
    color: var(--text-secondary);
    white-space: pre-wrap;
    word-break: break-word;
  }

  .action-bar {
    padding: 12px 20px;
    border-top: 1px solid var(--border);
  }

  .action-buttons {
    display: flex;
    gap: 8px;
  }

  .action-btn {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 6px 12px;
    border: 1px solid var(--border-light);
    background: var(--bg-tertiary);
    color: var(--text-secondary);
    font-size: 12px;
    font-family: 'Outfit', sans-serif;
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition: all 0.12s;
  }

  .action-btn:hover {
    background: var(--bg-hover);
    color: var(--text-primary);
    border-color: var(--accent);
  }

  .snooze-wrapper {
    position: relative;
  }

  .snooze-menu {
    position: absolute;
    bottom: 100%;
    left: 0;
    background: var(--bg-tertiary);
    border: 1px solid var(--border-light);
    border-radius: var(--radius-md);
    padding: 4px;
    box-shadow: var(--shadow);
    z-index: 10;
    margin-bottom: 4px;
  }

  .snooze-menu button {
    display: block;
    width: 100%;
    text-align: left;
    padding: 6px 12px;
    border: none;
    background: transparent;
    color: var(--text-secondary);
    font-size: 12px;
    font-family: 'Outfit', sans-serif;
    cursor: pointer;
    border-radius: 4px;
    white-space: nowrap;
  }

  .snooze-menu button:hover {
    background: var(--bg-hover);
    color: var(--text-primary);
  }

  .reply-section {
    padding: 16px 20px;
    border-top: 1px solid var(--border);
  }

  textarea {
    width: 100%;
    background: var(--bg-tertiary);
    border: 1px solid var(--border-light);
    color: var(--text-primary);
    font-family: 'Outfit', sans-serif;
    font-size: 13px;
    padding: 10px 12px;
    border-radius: var(--radius-md);
    resize: vertical;
    outline: none;
    transition: border-color 0.15s;
  }

  textarea:focus {
    border-color: var(--accent);
  }

  .reply-footer {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-top: 10px;
  }

  .reply-hint {
    font-size: 11px;
    color: var(--text-muted);
    font-family: var(--mono);
  }

  .send-btn {
    padding: 6px 16px;
    background: var(--accent);
    color: white;
    border: none;
    border-radius: var(--radius-sm);
    font-family: 'Outfit', sans-serif;
    font-size: 12px;
    font-weight: 500;
    cursor: pointer;
    transition: background 0.15s;
  }

  .send-btn:hover:not(:disabled) {
    background: var(--accent-hover);
  }

  .send-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .empty-detail {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    color: var(--text-muted);
    background: var(--bg-secondary);
    border-left: 1px solid var(--border);
  }

  .empty-icon {
    font-size: 48px;
    margin-bottom: 16px;
    opacity: 0.5;
  }

  .empty-detail p {
    font-size: 14px;
    margin-bottom: 4px;
  }

  .empty-hint {
    font-size: 12px;
    font-family: var(--mono);
    opacity: 0.6;
  }
</style>

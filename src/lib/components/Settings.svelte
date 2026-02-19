<!--
  Command Center - Settings Panel
  Shows service connection statuses and OAuth setup buttons.
-->
<script>
  import { showSettings, serviceStatuses } from '$lib/stores';
  import { api } from '$lib/api';
  import { onMount } from 'svelte';

  let gmailAccounts = [];
  let loading = true;

  onMount(async () => {
    await refreshAuthStatus();
  });

  async function refreshAuthStatus() {
    loading = true;
    try {
      const data = await api.getAuthStatus();
      gmailAccounts = data.gmail_accounts || [];
    } catch (e) {
      console.error('Failed to load auth status:', e);
    }
    loading = false;
  }

  function connectGmail(email) {
    // Open the OAuth URL in the system browser
    window.open(`http://127.0.0.1:8766/auth/google/start?email=${encodeURIComponent(email)}`, '_blank');
  }

  function close() {
    showSettings.set(false);
  }

  function handleKeydown(e) {
    if (e.key === 'Escape') close();
  }
</script>

<svelte:window on:keydown={handleKeydown} />

<div class="settings-overlay" on:click={close} on:keydown={handleKeydown} role="button" tabindex="-1">
  <div class="settings-panel" on:click|stopPropagation role="dialog">
    <div class="settings-header">
      <h2>Settings</h2>
      <button class="close-btn" on:click={close}>&#x2715;</button>
    </div>

    <div class="settings-body">
      <!-- Gmail Section -->
      <div class="section">
        <h3 class="section-title">Gmail Accounts</h3>
        {#if loading}
          <p class="loading-text">Loading...</p>
        {:else if gmailAccounts.length === 0}
          <p class="empty-text">No Gmail accounts configured. Add GMAIL_ACCOUNT_1 to your .env file.</p>
        {:else}
          {#each gmailAccounts as account}
            <div class="service-row">
              <div class="service-info">
                <span class="service-icon" style="color: var(--gmail)">&#x2709;</span>
                <span class="service-email">{account.email}</span>
              </div>
              {#if account.connected}
                <span class="status-badge connected">Connected</span>
              {:else}
                <button class="connect-btn" on:click={() => connectGmail(account.email)}>
                  Connect
                </button>
              {/if}
            </div>
          {/each}
        {/if}
      </div>

      <!-- Slack Section -->
      <div class="section">
        <h3 class="section-title">Slack Workspaces <span class="read-only-tag">read-only</span></h3>
        {#if $serviceStatuses.filter(s => s.service === 'slack').length === 0}
          <p class="empty-text">No Slack workspaces configured. Add tokens to your .env file.</p>
        {:else}
          {#each $serviceStatuses.filter(s => s.service === 'slack') as status}
            <div class="service-row">
              <div class="service-info">
                <span class="service-icon" style="color: var(--slack)">&#x1F4AC;</span>
                <span class="service-email">{status.account}</span>
              </div>
              <span class="status-badge" class:connected={status.connected}>
                {status.connected ? 'Connected' : 'Disconnected'}
              </span>
            </div>
          {/each}
        {/if}
      </div>

      <!-- Other services -->
      <div class="section">
        <h3 class="section-title">Other Services</h3>
        {#each $serviceStatuses.filter(s => s.service !== 'gmail' && s.service !== 'slack') as status}
          <div class="service-row">
            <div class="service-info">
              <span class="service-email">{status.service}: {status.account}</span>
            </div>
            <span class="status-badge" class:connected={status.connected}>
              {status.connected ? 'Connected' : 'Disconnected'}
            </span>
          </div>
        {:else}
          <p class="empty-text">No additional services configured.</p>
        {/each}
      </div>
    </div>

    <div class="settings-footer">
      <button class="refresh-btn" on:click={refreshAuthStatus} disabled={loading}>
        Refresh Status
      </button>
    </div>
  </div>
</div>

<style>
  .settings-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.6);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 100;
  }

  .settings-panel {
    width: 480px;
    max-height: 80vh;
    background: var(--bg-secondary);
    border: 1px solid var(--border-light);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow);
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .settings-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 20px 24px;
    border-bottom: 1px solid var(--border);
  }

  .settings-header h2 {
    font-size: 16px;
    font-weight: 600;
    color: var(--text-primary);
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

  .settings-body {
    flex: 1;
    padding: 20px 24px;
    overflow-y: auto;
  }

  .section {
    margin-bottom: 24px;
  }

  .section:last-child {
    margin-bottom: 0;
  }

  .section-title {
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 1.5px;
    text-transform: uppercase;
    color: var(--text-muted);
    margin-bottom: 12px;
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .read-only-tag {
    font-size: 9px;
    font-weight: 500;
    letter-spacing: 0.5px;
    text-transform: lowercase;
    padding: 1px 6px;
    background: var(--bg-tertiary);
    border: 1px solid var(--border-light);
    border-radius: 4px;
    color: var(--text-muted);
  }

  .service-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 12px;
    background: var(--bg-tertiary);
    border-radius: var(--radius-sm);
    margin-bottom: 6px;
  }

  .service-info {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .service-icon {
    font-size: 16px;
  }

  .service-email {
    font-size: 13px;
    color: var(--text-secondary);
    font-family: var(--mono);
  }

  .status-badge {
    font-size: 11px;
    font-weight: 500;
    padding: 2px 8px;
    border-radius: 4px;
    background: rgba(239, 68, 68, 0.15);
    color: #ef4444;
  }

  .status-badge.connected {
    background: rgba(34, 197, 94, 0.15);
    color: #22c55e;
  }

  .connect-btn {
    padding: 4px 12px;
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

  .connect-btn:hover {
    background: var(--accent-hover);
  }

  .empty-text, .loading-text {
    font-size: 12px;
    color: var(--text-muted);
    padding: 8px 12px;
  }

  .settings-footer {
    padding: 16px 24px;
    border-top: 1px solid var(--border);
  }

  .refresh-btn {
    padding: 6px 14px;
    background: var(--bg-tertiary);
    color: var(--text-secondary);
    border: 1px solid var(--border-light);
    border-radius: var(--radius-sm);
    font-family: 'Outfit', sans-serif;
    font-size: 12px;
    cursor: pointer;
    transition: all 0.15s;
  }

  .refresh-btn:hover:not(:disabled) {
    background: var(--bg-hover);
    color: var(--text-primary);
    border-color: var(--accent);
  }

  .refresh-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>

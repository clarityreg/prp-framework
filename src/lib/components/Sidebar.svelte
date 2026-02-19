<!--
  Command Center - Sidebar
  Filter by source, see badge counts, service status at a glance.
-->
<script>
  import { activeFilter, unreadCounts, serviceStatuses, showTaskCreator, showSettings } from '$lib/stores';
  import { SOURCE_CONFIG } from '$lib/types';

  const sources = ['all', 'gmail', 'outlook', 'slack', 'asana', 'plane'];

  function setFilter(source) {
    activeFilter.set(source);
  }

  // Keyboard shortcuts
  function handleKeydown(e) {
    if (e.metaKey || e.ctrlKey) {
      const num = parseInt(e.key);
      if (num >= 1 && num <= sources.length) {
        e.preventDefault();
        setFilter(sources[num - 1]);
      }
      if (e.key === 'n') {
        e.preventDefault();
        showTaskCreator.set(true);
      }
    }
  }
</script>

<svelte:window on:keydown={handleKeydown} />

<aside class="sidebar">
  <div class="sidebar-header">
    <div class="logo">
      <span class="logo-icon">⚡</span>
      <span class="logo-text">CMD</span>
    </div>
  </div>

  <nav class="nav-section">
    <div class="nav-label">INBOX</div>
    {#each sources as source, i}
      {@const isAll = source === 'all'}
      {@const config = isAll ? { label: 'All', color: '#6366f1', icon: '📥' } : SOURCE_CONFIG[source]}
      {@const count = isAll ? $unreadCounts.total : ($unreadCounts[source] || 0)}
      {@const isActive = $activeFilter === source}

      <button
        class="nav-item"
        class:active={isActive}
        on:click={() => setFilter(source)}
        title="⌘{i + 1}"
      >
        <span class="nav-icon">{config.icon}</span>
        <span class="nav-label-text">{config.label}</span>
        {#if count > 0}
          <span class="badge" style="background: {config.color}">{count}</span>
        {/if}
        <span class="shortcut">⌘{i + 1}</span>
      </button>
    {/each}
  </nav>

  <div class="nav-section">
    <div class="nav-label">ACTIONS</div>
    <button class="nav-item action-btn" on:click={() => showTaskCreator.set(true)}>
      <span class="nav-icon">➕</span>
      <span class="nav-label-text">New Task</span>
      <span class="shortcut">⌘N</span>
    </button>
  </div>

  <div class="sidebar-footer">
    <button class="settings-btn" on:click={() => showSettings.set(true)}>
      <span>&#x2699;</span> Settings
    </button>
    <div class="status-dots">
      {#each $serviceStatuses as status}
        <span
          class="status-dot"
          class:connected={status.connected}
          title="{status.service}: {status.connected ? 'Connected' : 'Disconnected'} ({status.account})"
        ></span>
      {/each}
    </div>
  </div>
</aside>

<style>
  .sidebar {
    width: 220px;
    min-width: 220px;
    background: var(--bg-secondary);
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    padding: 16px 0;
    user-select: none;
    -webkit-app-region: drag;
  }

  .sidebar-header {
    padding: 0 20px 20px;
    -webkit-app-region: drag;
  }

  .logo {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .logo-icon {
    font-size: 20px;
  }

  .logo-text {
    font-family: var(--mono);
    font-weight: 600;
    font-size: 16px;
    letter-spacing: 2px;
    color: var(--text-primary);
  }

  .nav-section {
    padding: 0 12px;
    margin-bottom: 24px;
  }

  .nav-label {
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 1.5px;
    color: var(--text-muted);
    padding: 0 8px;
    margin-bottom: 8px;
  }

  .nav-item {
    -webkit-app-region: no-drag;
    display: flex;
    align-items: center;
    gap: 10px;
    width: 100%;
    padding: 8px 12px;
    border: none;
    background: transparent;
    color: var(--text-secondary);
    font-family: 'Outfit', sans-serif;
    font-size: 13px;
    font-weight: 400;
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition: all 0.15s ease;
  }

  .nav-item:hover {
    background: var(--bg-hover);
    color: var(--text-primary);
  }

  .nav-item.active {
    background: var(--bg-active);
    color: var(--text-primary);
    font-weight: 500;
  }

  .nav-icon {
    font-size: 14px;
    width: 20px;
    text-align: center;
  }

  .nav-label-text {
    flex: 1;
    text-align: left;
  }

  .badge {
    font-size: 10px;
    font-weight: 600;
    color: white;
    padding: 1px 6px;
    border-radius: 10px;
    min-width: 18px;
    text-align: center;
    font-family: var(--mono);
  }

  .shortcut {
    font-size: 10px;
    color: var(--text-muted);
    font-family: var(--mono);
    opacity: 0;
    transition: opacity 0.15s;
  }

  .nav-item:hover .shortcut {
    opacity: 1;
  }

  .action-btn {
    border: 1px dashed var(--border-light);
    margin-top: 4px;
  }

  .sidebar-footer {
    margin-top: auto;
    padding: 12px 20px;
  }

  .settings-btn {
    -webkit-app-region: no-drag;
    display: flex;
    align-items: center;
    gap: 6px;
    width: 100%;
    padding: 6px 8px;
    margin-bottom: 10px;
    border: none;
    background: transparent;
    color: var(--text-muted);
    font-family: 'Outfit', sans-serif;
    font-size: 12px;
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition: all 0.15s;
  }

  .settings-btn:hover {
    background: var(--bg-hover);
    color: var(--text-primary);
  }

  .status-dots {
    display: flex;
    gap: 6px;
  }

  .status-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: #ef4444;
    transition: background 0.3s;
  }

  .status-dot.connected {
    background: #22c55e;
  }
</style>

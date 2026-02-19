<!--
  Command Center - Main Page
  The unified inbox: sidebar + notification feed + detail panel.
  Three-column layout like modern email clients.
-->
<script>
  import Sidebar from '$lib/components/Sidebar.svelte';
  import NotificationCard from '$lib/components/NotificationCard.svelte';
  import DetailPanel from '$lib/components/DetailPanel.svelte';
  import TaskCreator from '$lib/components/TaskCreator.svelte';
  import Settings from '$lib/components/Settings.svelte';
  import {
    filteredNotifications,
    searchQuery,
    selectedNotification,
    unreadCounts,
    activeFilter,
    showSettings,
  } from '$lib/stores';
  import { SOURCE_CONFIG } from '$lib/types';

  // Keyboard navigation for notification list
  function handleKeydown(e) {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;

    const items = $filteredNotifications;
    const currentIdx = items.findIndex(n => n.id === $selectedNotification?.id);

    if (e.key === 'ArrowDown' || e.key === 'j') {
      e.preventDefault();
      const nextIdx = currentIdx < items.length - 1 ? currentIdx + 1 : 0;
      selectedNotification.set(items[nextIdx] || null);
    }

    if (e.key === 'ArrowUp' || e.key === 'k') {
      e.preventDefault();
      const prevIdx = currentIdx > 0 ? currentIdx - 1 : items.length - 1;
      selectedNotification.set(items[prevIdx] || null);
    }
  }

  $: filterLabel = $activeFilter === 'all' ? 'All' : SOURCE_CONFIG[$activeFilter]?.label || 'All';
</script>

<svelte:window on:keydown={handleKeydown} />

<Sidebar />

<main class="inbox-container">
  <!-- Search + Header -->
  <div class="inbox-header">
    <div class="header-title">
      <h1>{filterLabel}</h1>
      <span class="count">{$filteredNotifications.length} items</span>
    </div>
    <div class="search-box">
      <span class="search-icon">🔍</span>
      <input
        type="text"
        placeholder="Search notifications..."
        bind:value={$searchQuery}
      />
      {#if $searchQuery}
        <button class="clear-search" on:click={() => searchQuery.set('')}>✕</button>
      {/if}
    </div>
  </div>

  <!-- Notification Feed -->
  <div class="notification-feed">
    {#if $filteredNotifications.length === 0}
      <div class="empty-state">
        <div class="empty-icon">🎯</div>
        <p class="empty-title">
          {$searchQuery ? 'No results found' : 'All caught up!'}
        </p>
        <p class="empty-subtitle">
          {$searchQuery
            ? 'Try a different search term'
            : 'No unread notifications. Take a break ☕'}
        </p>
      </div>
    {:else}
      {#each $filteredNotifications as notification (notification.id)}
        <NotificationCard {notification} />
      {/each}
    {/if}
  </div>
</main>

<DetailPanel />
<TaskCreator />
{#if $showSettings}
  <Settings />
{/if}

<style>
  .inbox-container {
    flex: 1;
    min-width: 320px;
    max-width: 480px;
    display: flex;
    flex-direction: column;
    background: var(--bg-primary);
    border-right: 1px solid var(--border);
  }

  .inbox-header {
    padding: 16px 16px 12px;
    border-bottom: 1px solid var(--border);
  }

  .header-title {
    display: flex;
    align-items: baseline;
    gap: 8px;
    margin-bottom: 12px;
  }

  .header-title h1 {
    font-size: 18px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .count {
    font-size: 12px;
    color: var(--text-muted);
    font-family: var(--mono);
  }

  .search-box {
    display: flex;
    align-items: center;
    gap: 8px;
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    padding: 0 12px;
    transition: border-color 0.15s;
  }

  .search-box:focus-within {
    border-color: var(--accent);
  }

  .search-icon {
    font-size: 13px;
    opacity: 0.5;
  }

  .search-box input {
    flex: 1;
    background: transparent;
    border: none;
    color: var(--text-primary);
    font-family: 'Outfit', sans-serif;
    font-size: 13px;
    padding: 8px 0;
    outline: none;
  }

  .search-box input::placeholder {
    color: var(--text-muted);
  }

  .clear-search {
    border: none;
    background: transparent;
    color: var(--text-muted);
    cursor: pointer;
    font-size: 12px;
    padding: 2px;
  }

  .clear-search:hover {
    color: var(--text-primary);
  }

  .notification-feed {
    flex: 1;
    overflow-y: auto;
  }

  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 60px 20px;
    text-align: center;
  }

  .empty-icon {
    font-size: 40px;
    margin-bottom: 16px;
    opacity: 0.6;
  }

  .empty-title {
    font-size: 15px;
    font-weight: 500;
    color: var(--text-secondary);
    margin-bottom: 4px;
  }

  .empty-subtitle {
    font-size: 13px;
    color: var(--text-muted);
  }
</style>

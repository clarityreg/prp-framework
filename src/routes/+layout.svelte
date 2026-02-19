<!--
  Command Center - Root Layout
  Dark theme, clean typography, the shell that wraps everything.
  Waits for the Python backend to start before connecting.
-->
<script>
  import { onMount, onDestroy } from 'svelte';
  import { connectWebSocket, disconnectWebSocket, waitForBackend } from '$lib/ws';
  import { backendStatus } from '$lib/stores';

  let retrying = false;

  async function startApp() {
    retrying = false;
    try {
      await waitForBackend();
      connectWebSocket();
    } catch (e) {
      console.error('[App] Backend startup failed:', e);
    }
  }

  function retry() {
    retrying = true;
    $backendStatus = 'waiting';
    startApp();
  }

  onMount(() => {
    startApp();
  });

  onDestroy(() => {
    disconnectWebSocket();
  });
</script>

{#if $backendStatus === 'ready'}
  <div class="app-shell">
    <slot />
  </div>
{:else if $backendStatus === 'error'}
  <div class="splash-screen">
    <div class="splash-content">
      <div class="splash-icon">&#x26A0;</div>
      <h2>Backend Unavailable</h2>
      <p>Could not connect to the backend server after 30 seconds.</p>
      <p class="splash-hint">Make sure the Python backend is running on port 8766.</p>
      <button class="retry-btn" on:click={retry} disabled={retrying}>
        {retrying ? 'Retrying...' : 'Retry Connection'}
      </button>
    </div>
  </div>
{:else}
  <div class="splash-screen">
    <div class="splash-content">
      <div class="spinner"></div>
      <h2>Starting Command Center</h2>
      <p>Waiting for backend services...</p>
    </div>
  </div>
{/if}

<style>
  :global(*) {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
  }

  :global(body) {
    font-family: 'Outfit', -apple-system, sans-serif;
    background: #0a0a0f;
    color: #e4e4e7;
    overflow: hidden;
    height: 100vh;
    -webkit-font-smoothing: antialiased;
  }

  :global(::-webkit-scrollbar) {
    width: 6px;
  }
  :global(::-webkit-scrollbar-track) {
    background: transparent;
  }
  :global(::-webkit-scrollbar-thumb) {
    background: #27272a;
    border-radius: 3px;
  }
  :global(::-webkit-scrollbar-thumb:hover) {
    background: #3f3f46;
  }

  .app-shell {
    height: 100vh;
    display: flex;
    background: #0a0a0f;
  }

  .splash-screen {
    height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    background: #0a0a0f;
  }

  .splash-content {
    text-align: center;
    color: var(--text-muted);
  }

  .splash-content h2 {
    font-size: 20px;
    font-weight: 500;
    color: var(--text-primary);
    margin-bottom: 8px;
  }

  .splash-content p {
    font-size: 13px;
    margin-bottom: 4px;
  }

  .splash-hint {
    font-family: var(--mono);
    font-size: 11px !important;
    opacity: 0.6;
    margin-top: 8px !important;
  }

  .splash-icon {
    font-size: 48px;
    margin-bottom: 16px;
    opacity: 0.7;
  }

  .spinner {
    width: 32px;
    height: 32px;
    border: 3px solid var(--border-light);
    border-top-color: var(--accent);
    border-radius: 50%;
    margin: 0 auto 20px;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  .retry-btn {
    margin-top: 20px;
    padding: 8px 20px;
    background: var(--accent);
    color: white;
    border: none;
    border-radius: var(--radius-sm);
    font-family: 'Outfit', sans-serif;
    font-size: 13px;
    font-weight: 500;
    cursor: pointer;
    transition: background 0.15s;
  }

  .retry-btn:hover:not(:disabled) {
    background: var(--accent-hover);
  }

  .retry-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  /* CSS Custom Properties for the design system */
  :global(:root) {
    --bg-primary: #0a0a0f;
    --bg-secondary: #111118;
    --bg-tertiary: #18181f;
    --bg-hover: #1e1e28;
    --bg-active: #252530;

    --border: #1e1e2a;
    --border-light: #2a2a38;

    --text-primary: #e4e4e7;
    --text-secondary: #a1a1aa;
    --text-muted: #71717a;

    --accent: #6366f1;
    --accent-hover: #818cf8;

    --gmail: #EA4335;
    --outlook: #0078D4;
    --slack: #4A154B;
    --asana: #F06A6A;
    --plane: #3F76FF;

    --urgent: #EF4444;
    --high: #F97316;
    --normal: #6B7280;
    --low: #9CA3AF;

    --radius-sm: 6px;
    --radius-md: 10px;
    --radius-lg: 14px;

    --shadow: 0 4px 24px rgba(0, 0, 0, 0.4);

    --mono: 'JetBrains Mono', monospace;
  }
</style>

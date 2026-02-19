<!--
  Command Center - Task Creator Modal
  Create a new task in Plane (default) or Asana (for specific client).
-->
<script>
  import { showTaskCreator, selectedNotification } from '$lib/stores';
  import { api } from '$lib/api';

  let title = '';
  let description = '';
  let target = 'plane';
  let priority = 'normal';
  let isCreating = false;
  let success = false;

  // Pre-fill from selected notification if available
  $: if ($showTaskCreator && $selectedNotification) {
    title = title || $selectedNotification.title;
    description = description || $selectedNotification.body;
  }

  async function create() {
    if (!title.trim()) return;
    isCreating = true;
    try {
      await api.createTask({
        title,
        description,
        target,
        priority,
        source_notification_id: $selectedNotification?.id,
      });
      success = true;
      setTimeout(() => {
        close();
      }, 1000);
    } catch (e) {
      console.error('Failed to create task:', e);
    }
    isCreating = false;
  }

  function close() {
    showTaskCreator.set(false);
    title = '';
    description = '';
    target = 'plane';
    priority = 'normal';
    success = false;
  }

  function handleKeydown(e) {
    if (e.key === 'Escape') close();
    if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') create();
  }
</script>

{#if $showTaskCreator}
  <div class="overlay" on:click={close} on:keydown={handleKeydown} role="dialog" tabindex="-1">
    <div class="modal" on:click|stopPropagation role="document">
      {#if success}
        <div class="success">
          <div class="success-icon">✅</div>
          <p>Task created in {target === 'plane' ? 'Plane' : 'Asana'}!</p>
        </div>
      {:else}
        <div class="modal-header">
          <h3>Create Task</h3>
          <button class="close-btn" on:click={close}>✕</button>
        </div>

        <div class="modal-body">
          <div class="field">
            <label for="title">Title</label>
            <input
              id="title"
              bind:value={title}
              placeholder="Task title..."
              autofocus
            />
          </div>

          <div class="field">
            <label for="description">Description</label>
            <textarea
              id="description"
              bind:value={description}
              placeholder="Optional description..."
              rows="4"
            ></textarea>
          </div>

          <div class="field-row">
            <div class="field">
              <label for="target">Create in</label>
              <select id="target" bind:value={target}>
                <option value="plane">✈️ Plane (Default)</option>
                <option value="asana">📋 Asana (Client)</option>
              </select>
            </div>

            <div class="field">
              <label for="priority">Priority</label>
              <select id="priority" bind:value={priority}>
                <option value="urgent">🔴 Urgent</option>
                <option value="high">🟠 High</option>
                <option value="normal">⚪ Normal</option>
                <option value="low">🔵 Low</option>
              </select>
            </div>
          </div>
        </div>

        <div class="modal-footer">
          <span class="hint">⌘ + Enter to create</span>
          <div class="footer-buttons">
            <button class="btn-secondary" on:click={close}>Cancel</button>
            <button class="btn-primary" disabled={!title.trim() || isCreating} on:click={create}>
              {isCreating ? 'Creating...' : 'Create Task'}
            </button>
          </div>
        </div>
      {/if}
    </div>
  </div>
{/if}

<svelte:window on:keydown={$showTaskCreator ? handleKeydown : undefined} />

<style>
  .overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.6);
    backdrop-filter: blur(4px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 100;
  }

  .modal {
    width: 480px;
    max-width: 90vw;
    background: var(--bg-secondary);
    border: 1px solid var(--border-light);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow);
    overflow: hidden;
  }

  .modal-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 16px 20px;
    border-bottom: 1px solid var(--border);
  }

  .modal-header h3 {
    font-size: 15px;
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
    font-size: 14px;
  }

  .close-btn:hover {
    background: var(--bg-hover);
    color: var(--text-primary);
  }

  .modal-body {
    padding: 20px;
  }

  .field {
    margin-bottom: 16px;
    flex: 1;
  }

  .field label {
    display: block;
    font-size: 11px;
    font-weight: 600;
    color: var(--text-muted);
    letter-spacing: 0.5px;
    text-transform: uppercase;
    margin-bottom: 6px;
  }

  .field input,
  .field textarea,
  .field select {
    width: 100%;
    background: var(--bg-tertiary);
    border: 1px solid var(--border-light);
    color: var(--text-primary);
    font-family: 'Outfit', sans-serif;
    font-size: 13px;
    padding: 8px 12px;
    border-radius: var(--radius-sm);
    outline: none;
    transition: border-color 0.15s;
  }

  .field input:focus,
  .field textarea:focus,
  .field select:focus {
    border-color: var(--accent);
  }

  .field select {
    cursor: pointer;
  }

  .field-row {
    display: flex;
    gap: 12px;
  }

  .modal-footer {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 20px;
    border-top: 1px solid var(--border);
  }

  .hint {
    font-size: 11px;
    color: var(--text-muted);
    font-family: var(--mono);
  }

  .footer-buttons {
    display: flex;
    gap: 8px;
  }

  .btn-secondary {
    padding: 6px 14px;
    background: var(--bg-tertiary);
    border: 1px solid var(--border-light);
    color: var(--text-secondary);
    font-family: 'Outfit', sans-serif;
    font-size: 12px;
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .btn-secondary:hover {
    background: var(--bg-hover);
  }

  .btn-primary {
    padding: 6px 16px;
    background: var(--accent);
    color: white;
    border: none;
    font-family: 'Outfit', sans-serif;
    font-size: 12px;
    font-weight: 500;
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition: background 0.15s;
  }

  .btn-primary:hover:not(:disabled) {
    background: var(--accent-hover);
  }

  .btn-primary:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .success {
    padding: 48px 20px;
    text-align: center;
  }

  .success-icon {
    font-size: 36px;
    margin-bottom: 12px;
  }

  .success p {
    font-size: 14px;
    color: var(--text-secondary);
  }
</style>

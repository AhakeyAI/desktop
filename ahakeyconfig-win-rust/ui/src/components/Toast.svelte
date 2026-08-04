<script lang="ts">
  import { toasts } from "../stores/ui";
</script>

<div class="toast-container">
  {#each $toasts as t (t.id)}
    <div class="toast {t.type}">
      <span class="icon">
        {#if t.type === "success"}✓
        {:else if t.type === "warning"}⚠
        {:else if t.type === "error"}✕
        {:else}ℹ{/if}
      </span>
      <span class="message">{t.message}</span>
    </div>
  {/each}
</div>

<style>
  .toast-container {
    position: fixed;
    top: 80px;
    right: 20px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    z-index: 1000;
    pointer-events: none;
  }
  .toast {
    background: rgba(255, 255, 255, 0.96);
    border: 1px solid #e4e8ef;
    border-radius: 10px;
    padding: 10px 16px;
    box-shadow: 0 8px 24px rgba(15, 23, 42, 0.12);
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 13px;
    min-width: 200px;
    max-width: 360px;
    animation: slideIn 0.2s ease-out;
    pointer-events: auto;
  }
  .icon {
    font-weight: 700;
    font-size: 16px;
    line-height: 1;
  }
  .message {
    color: var(--text-primary);
    flex: 1;
  }
  .toast.info { border-left: 3px solid var(--brand-blue); }
  .toast.info .icon { color: var(--brand-blue); }
  .toast.success { border-left: 3px solid var(--green-dark); }
  .toast.success .icon { color: var(--green-dark); }
  .toast.warning { border-left: 3px solid var(--orange); }
  .toast.warning .icon { color: var(--orange); }
  .toast.error { border-left: 3px solid var(--red-dark); }
  .toast.error .icon { color: var(--red-dark); }
  @keyframes slideIn {
    from { transform: translateX(20px); opacity: 0; }
    to { transform: translateX(0); opacity: 1; }
  }
</style>

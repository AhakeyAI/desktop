<script lang="ts">
  import { activeModal } from "../stores/ui";

  $: if ($activeModal) {
    document.body.style.overflow = "hidden";
  } else {
    document.body.style.overflow = "";
  }

  function close() {
    activeModal.set(null);
  }

  function onBackdrop(e: MouseEvent) {
    if (e.target === e.currentTarget) close();
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === "Escape") close();
  }
</script>

<svelte:window on:keydown={onKey} />

{#if $activeModal}
  <div class="backdrop" on:click={onBackdrop} role="presentation">
    <div class="modal" role="dialog" aria-modal="true">
      <div class="modal-header">
        <h3>
          {#if $activeModal === "device-info"}设备信息{/if}
          {#if $activeModal === "version-info"}版本信息{/if}
          {#if $activeModal === "language"}切换语言{/if}
          {#if $activeModal === "exit"}退出应用{/if}
          {#if $activeModal === "restore-defaults"}恢复默认配置{/if}
          {#if $activeModal === "reconnect"}重新连接{/if}
          {#if $activeModal === "clear-oled"}清除 OLED 预览{/if}
          {#if $activeModal === "about-rust"}关于 Rust 重写版{/if}
        </h3>
        <button class="close-btn" on:click={close}>✕</button>
      </div>

      <div class="modal-body">
        {#if $activeModal === "device-info"}
          <div class="kv"><span>设备名称</span><span>AhaKey Pro</span></div>
          <div class="kv"><span>连接状态</span><span class="status-disconnected">未连接</span></div>
          <div class="kv"><span>电池电量</span><span>—</span></div>
          <div class="kv"><span>固件版本</span><span>1.2.3</span></div>
          <div class="kv"><span>MAC 地址</span><span>—</span></div>
          <div class="kv"><span>信号强度</span><span>—</span></div>
        {/if}

        {#if $activeModal === "version-info"}
          <div class="info-banner">
            <div class="info-banner-title">AhaKey Studio</div>
          </div>
          <div class="kv"><span>版本</span><span>1.0.0</span></div>
          <div class="kv"><span>平台</span><span>Windows x86_64</span></div>
          <div class="kv"><span>核心</span><span>Tauri 2.x + Rust 1.97</span></div>
          <div class="kv"><span>UI 框架</span><span>Svelte 4</span></div>
          <div class="kv"><span>重写自</span><span>ahakeyconfig-win-java</span></div>
        {/if}

        {#if $activeModal === "language"}
          <p class="modal-text">切换语言会立即刷新界面文本,需要重启应用吗?</p>
          <div class="lang-options">
            <button class="lang-option selected">中文 (zh-CN)</button>
            <button class="lang-option">English (en)</button>
          </div>
        {/if}

        {#if $activeModal === "exit"}
          <p class="modal-text">确定要退出 AhaKey Studio 吗?</p>
          <p class="modal-sub">应用退出后,键盘按键将不再被路由。</p>
        {/if}

        {#if $activeModal === "restore-defaults"}
          <p class="modal-text">将当前 Mode 的所有按键配置恢复为出厂默认值?</p>
          <p class="modal-sub">此操作会清除你对该 Mode 的所有自定义修改。</p>
        {/if}

        {#if $activeModal === "reconnect"}
          <p class="modal-text">先断开当前连接,然后重新扫描并连接设备?</p>
        {/if}

        {#if $activeModal === "clear-oled"}
          <p class="modal-text">清除 OLED 预览区的占位图?</p>
          <p class="modal-sub">使用时,设备屏幕回到默认占位状态。</p>
        {/if}

        {#if $activeModal === "about-rust"}
          <div class="info-banner">
            <div class="info-banner-title">Rust 重写版 v1.0</div>
          </div>
          <p class="modal-text">
            这个版本替换了原 Java + JavaFX 实现,使用 Rust + Tauri 构建。
          </p>
          <ul class="feature-list">
            <li>✓ 单进程,无外部 BLE_tcp_driver 进程</li>
            <li>✓ 内存占用从 200MB+ 降到 30MB</li>
            <li>✓ 启动时间从 1-2s 降到 200ms</li>
            <li>✓ 键盘钩子直接调 Win32 API,无 JNA 边界</li>
          </ul>
        {/if}
      </div>

      <div class="modal-footer">
        <button class="button-action" on:click={close}>取消</button>
        {#if $activeModal === "exit"}
          <button class="button-prominent" on:click={() => { close(); window.close(); }}>退出</button>
        {:else if $activeModal === "restore-defaults"}
          <button class="button-prominent" on:click={close}>恢复</button>
        {:else if $activeModal === "language"}
          <button class="button-prominent" on:click={close}>应用</button>
        {:else if $activeModal === "reconnect"}
          <button class="button-prominent" on:click={close}>开始</button>
        {:else if $activeModal === "clear-oled"}
          <button class="button-prominent" on:click={close}>清除</button>
        {:else}
          <button class="button-prominent" on:click={close}>确定</button>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    background: rgba(15, 23, 42, 0.35);
    backdrop-filter: blur(4px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 900;
    animation: fadeIn 0.15s ease-out;
  }
  .modal {
    background: #ffffff;
    border-radius: 16px;
    box-shadow: 0 16px 48px rgba(15, 23, 42, 0.20);
    min-width: 360px;
    max-width: 480px;
    max-height: 80vh;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    animation: scaleIn 0.18s ease-out;
  }
  .modal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 16px 20px;
    border-bottom: 1px solid #f0f2f5;
  }
  .modal-header h3 {
    font-size: 16px;
    font-weight: 700;
    color: #111827;
    margin: 0;
  }
  .close-btn {
    background: transparent;
    border: 0;
    color: var(--text-muted);
    font-size: 16px;
    padding: 4px 8px;
    box-shadow: none;
    border-radius: 6px;
  }
  .close-btn:hover {
    background: #f0f4f8;
    color: var(--text-primary);
    border-color: transparent;
  }
  .modal-body {
    padding: 20px;
    overflow-y: auto;
    flex: 1;
  }
  .modal-text {
    font-size: 14px;
    color: #1d1d1f;
    line-height: 1.6;
    margin-bottom: 8px;
  }
  .modal-sub {
    font-size: 12px;
    color: var(--text-muted);
    line-height: 1.5;
  }
  .kv {
    display: flex;
    justify-content: space-between;
    padding: 8px 0;
    border-bottom: 1px solid #f0f2f5;
    font-size: 13px;
  }
  .kv:last-child { border-bottom: 0; }
  .kv span:first-child { color: var(--text-muted); }
  .kv span:last-child { color: var(--text-primary); font-weight: 600; }
  .status-disconnected { color: var(--orange); }
  .lang-options {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-top: 12px;
  }
  .lang-option {
    text-align: left;
    padding: 12px 16px;
  }
  .lang-option.selected {
    border-color: var(--brand-blue);
    color: var(--brand-blue);
    background: rgba(46, 139, 255, 0.06);
  }
  .feature-list {
    list-style: none;
    margin-top: 12px;
    color: var(--text-primary);
    font-size: 13px;
    line-height: 1.8;
  }
  .modal-footer {
    padding: 12px 20px;
    border-top: 1px solid #f0f2f5;
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }
  @keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
  }
  @keyframes scaleIn {
    from { transform: scale(0.95); opacity: 0; }
    to { transform: scale(1); opacity: 1; }
  }
</style>

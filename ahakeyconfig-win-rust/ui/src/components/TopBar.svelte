<script lang="ts">
  import { createEventDispatcher, onMount, tick } from "svelte";

  export let connected: boolean = false;
  export let deviceName: string = "";
  export let batteryLevel: number = 0;
  export let switchTitle: string = "手动批准";

  const dispatch = createEventDispatcher();
  let menuOpen = false;
  let menuBtn: HTMLElement;
  let dropdownStyle = "";

  function toggleMenu() {
    menuOpen = !menuOpen;
    if (menuOpen) updateDropdownPos();
  }

  async function updateDropdownPos() {
    await tick();
    if (!menuBtn) return;
    const r = menuBtn.getBoundingClientRect();
    dropdownStyle = `top: ${r.bottom + 4}px; right: ${window.innerWidth - r.right}px;`;
  }

  function handleMenu(action: string) {
    menuOpen = false;
    dispatch("menu", { action });
  }

  function onDocClick(e: MouseEvent) {
    if (!menuOpen) return;
    const target = e.target as HTMLElement;
    if (!target.closest(".toolbar-menu")) {
      menuOpen = false;
    }
  }

  $: connectionColor = connected ? "#30d158" : "#ff9f0a";
  $: batteryColor = "#0a84ff";
  $: switchColor = "#5e5ce6";

  onMount(() => {
    document.addEventListener("click", onDocClick);
    window.addEventListener("resize", () => { if (menuOpen) updateDropdownPos(); });
    return () => document.removeEventListener("click", onDocClick);
  });
</script>

<div class="top-bar">
  <div class="row">
    <div class="title-box">
      <span class="keyboard-icon">⌨</span>
      <span class="title">AhaKey Studio</span>
    </div>

    <div class="info-pill" style="border-color: {connectionColor}">
      <span class="info-pill-title">{connected ? "已连接" : "未连接"}</span>
      <span class="info-pill-subtitle">{connected ? deviceName : "等待设备..."}</span>
    </div>

    <div class="info-pill" style="border-color: {batteryColor}">
      <span class="info-pill-title">电量</span>
      <span class="info-pill-subtitle">{connected ? `${batteryLevel}%` : "—"}</span>
    </div>

    <div
      class="info-pill switch-pill"
      style="border-color: {switchColor}"
      title="摇杆档位(由硬件拨动决定,只读)"
    >
      <span class="info-pill-title">摇杆</span>
      <span class="info-pill-subtitle">{switchTitle}</span>
    </div>

    <button
      class={connected ? "button-disconnect" : "button-connect"}
      on:click={() => dispatch("toggleConnect")}
    >
      {connected ? "断开连接" : "连接设备"}
    </button>

    <button class="button-ble" on:click={() => dispatch("bleDriver")}>BLE 驱动</button>

    <div class="status-box">
      <div class="row">
        <span class="status-dot" style="background: #30d158;"></span>
        <div>
          <div class="status-label">键盘控制中</div>
          <div class="status-detail">键盘正常使用,直通设备</div>
        </div>
      </div>
    </div>

    <button class="button-prominent" on:click={() => dispatch("configMode")}>
      编辑配置
    </button>

    <div class="spacer"></div>

    <div class="toolbar-menu" class:open={menuOpen}>
      <button class="more-trigger" bind:this={menuBtn} on:click={toggleMenu}>
        ⋯ 更多
      </button>
    </div>
  </div>
</div>

{#if menuOpen}
  <div class="dropdown-portal" style={dropdownStyle}>
    <button class="item" on:click={() => handleMenu("restore-defaults")}>恢复默认</button>
    <button class="item" on:click={() => handleMenu("reconnect")}>重新连接</button>
    <button class="item" on:click={() => handleMenu("clear-oled")}>清除 OLED 预览</button>
    <div class="divider"></div>
    <button class="item" on:click={() => handleMenu("device-info")}>设备信息</button>
    <button class="item" on:click={() => handleMenu("version-info")}>版本信息</button>
    <button class="item" on:click={() => handleMenu("language")}>中 / EN</button>
    <div class="divider"></div>
    <button class="item" on:click={() => handleMenu("exit")}>退出</button>
  </div>
{/if}

<style>
  .title-box {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .keyboard-icon {
    font-size: 22px;
    color: var(--brand-blue);
  }
  .more-trigger {
    background: transparent;
    border: 0;
    padding: 0;
    font: inherit;
    color: inherit;
    cursor: pointer;
    box-shadow: none;
  }
  .more-trigger:hover {
    background: transparent;
    color: inherit;
    border-color: transparent;
  }

  /* Portal dropdown - 不受 flex layout / overflow 影响 */
  :global(.dropdown-portal) {
    position: fixed;
    background: #fff;
    border: 1px solid #e8e8ed;
    border-radius: 10px;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.10);
    min-width: 180px;
    z-index: 1000;
    display: flex;
    flex-direction: column;
    padding: 4px 0;
  }
  :global(.dropdown-portal .item) {
    display: block;
    padding: 10px 14px;
    font-size: 13px;
    color: #1d1d1f;
    cursor: pointer;
    border: 0;
    background: transparent;
    width: 100%;
    text-align: left;
    border-radius: 0;
    box-shadow: none;
    font-weight: 500;
    font-family: inherit;
  }
  :global(.dropdown-portal .item:hover) {
    background: #f5f5f7;
    color: var(--brand-blue);
  }
  :global(.dropdown-portal .divider) {
    height: 1px;
    background: #dfe4ee;
    margin: 4px 0;
  }
</style>

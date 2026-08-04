<script lang="ts">
  import { onMount } from "svelte";
  import { invoke } from "@tauri-apps/api/core";
  import { listen } from "@tauri-apps/api/event";
  import TopBar from "./components/TopBar.svelte";
  import StatusBar from "./components/StatusBar.svelte";
  import CanvasPane from "./components/CanvasPane.svelte";
  import InspectorPane from "./components/InspectorPane.svelte";
  import Toast from "./components/Toast.svelte";
  import Modal from "./components/Modal.svelte";
  import { activeModal, toastInfo, toastSuccess, toastWarning, toastError } from "./stores/ui";

  interface StudioState {
    connection: { connected: boolean; transport: string; device_address: string; latency_ms: number };
    device: { connected: boolean; device_name: string; firmware_version: string; battery_level: number; mode: number; charging: boolean; signal_strength: number };
    active_mode: number;
    active_route: string;
    parts: { name: string; enabled: boolean; role: string }[];
    aha_type_enabled: boolean;
    aha_type_status: string;
    language: string;
    switch_title: string;
  }

  interface ScanResult {
    address: string;
    name: string;
    rssi: number;
    matched_ahakey: boolean;
  }

  interface LastDevice {
    address: string;
    name: string;
  }

  let state: StudioState | null = null;
  let loadingMsg = "Loading...";

  let selectedMode = 0;
  const modeSlots = [
    { id: 0, name: "Claude" },
    { id: 1, name: "Cursor" },
    { id: 2, name: "Codex" },
    { id: 3, name: "Mode 4" },
  ];

  let selectedKeyId: number = 1;
  const keys = [
    { id: 1, label: "K1", name: "Record" },
    { id: 2, label: "K2", name: "Yes" },
    { id: 3, label: "K3", name: "No" },
    { id: 4, label: "K4", name: "Backspace" },
  ];

  const lightSegments = [0, 1, 2, 3, 4, 5, 6, 7];
  let unsavedCount = 0;

  // 扫描相关状态
  let scanning = false;
  let scanResults: ScanResult[] = [];
  let selectedDevice: ScanResult | null = null;
  let showDevicePicker = false;
  let connectError = "";

  // 上次连接的设备(用于快速重连 — 解决隐私设备扫不到的问题)
  let lastDevice: LastDevice | null = null;
  let reconnecting = false;

  // 过滤 + 排序:
  // 1. 过滤掉 RSSI 太弱(< -85)的噪音设备(离得很远的邻居设备)
  // 2. 但保留所有 matched_ahakey 设备(AhaKey 哪怕 -100 也要显示,用户能看到)
  // 3. 排序:mached_ahakey > AhaKey 名称 > 有名称 > 无名称,组内按 RSSI 降序
  $: sortedResults = scanResults
    .filter((d) => d.matched_ahakey || d.name.toLowerCase().includes('ahakey') || d.rssi >= -85)
    .sort((a, b) => {
      const score = (d: ScanResult) => {
        if (d.matched_ahakey && d.name.toLowerCase().includes('ahakey')) return 3000 + d.rssi;
        if (d.matched_ahakey) return 2500 + d.rssi;
        if (d.name.toLowerCase().includes('ahakey')) return 2000 + d.rssi;
        if (d.name) return 1000 + d.rssi;
        return d.rssi;
      };
      return score(b) - score(a);
    });

  onMount(async () => {
    try {
      state = await invoke<StudioState>("get_studio_state");
      if (state) selectedMode = state.active_mode;
    } catch (e) {
      loadingMsg = `Error: ${e}`;
    }

    // 监听后端推送的 device-status-changed 事件(BLE notify、摇杆、电量等)
    const unlisten = await listen<StudioState>("device-status-changed", (e) => {
      state = e.payload;
      document.title = `[AhaKey] ${e.payload.switch_title}`;
      if (state) selectedMode = state.active_mode;
    });

    return () => {
      unlisten();
    };
  });

  function onModeChange(e: CustomEvent<number>) {
    selectedMode = e.detail;
    unsavedCount += 1;
    toastInfo(`已切换到 ${modeSlots[e.detail]?.name}`);
  }

  function onKeyClick(e: CustomEvent<number>) {
    selectedKeyId = e.detail;
  }

  // ====================== 顶部按钮 ======================

  async function onToggleConnect() {
    console.log("[DEBUG] onToggleConnect clicked, state=", state);
    // 不依赖 state — 即使 state 还没加载完也能扫描
    if (state?.connection.connected) {
      try {
        await invoke("disconnect_device");
        toastInfo("已断开连接");
      } catch (e) {
        console.error("[DEBUG] disconnect error:", e);
        toastError(`断开失败: ${e}`);
      }
    } else {
      // 扫描设备 → 显示选择器
      await startScan();
    }
  }

  async function startScan() {
    console.log("[DEBUG] startScan begin");
    scanning = true;
    scanResults = [];
    selectedDevice = null;
    connectError = "";
    showDevicePicker = true;
    // 同时加载上次连接的设备(用于一键重连按钮)
    if (!lastDevice) {
      try {
        lastDevice = await invoke<LastDevice | null>("get_last_device");
      } catch (e) {
        console.error("[DEBUG] get_last_device error:", e);
      }
    }
    toastInfo("正在扫描 BLE 设备...");
    try {
      scanResults = await invoke<ScanResult[]>("scan_devices");
      console.log("[DEBUG] scan results:", scanResults);
      if (scanResults.length === 0) {
        toastWarning("未发现 BLE 设备,请确认设备已开机并在附近");
      } else {
        toastSuccess(`发现 ${scanResults.length} 台设备`);
      }
    } catch (e) {
      console.error("[DEBUG] scan error:", e);
      toastError(`扫描失败: ${e}`);
      showDevicePicker = false;
    } finally {
      scanning = false;
      console.log("[DEBUG] startScan end, showDevicePicker=", showDevicePicker);
    }
  }

  /// 一键重连上次设备:不依赖扫描,直接用持久化的 MAC 触发系统级连接。
  /// 适用于 AhaKey 设备在 BLE 隐私模式下扫描不到的情况。
  async function reconnectLastDevice() {
    if (reconnecting) return;
    reconnecting = true;
    try {
      // 先尝试读最新的 last_device(可能刚被其他流程保存)
      if (!lastDevice) {
        lastDevice = await invoke<LastDevice | null>("get_last_device");
      }
      if (!lastDevice) {
        toastWarning("未找到上次连接的设备,请先扫描并连接一次");
        return;
      }
      toastInfo(`正在重连 ${lastDevice.name || lastDevice.address}...`);
      await invoke("reconnect_last_device");
      showDevicePicker = false;
      toastSuccess(`已连接到 ${lastDevice.name || lastDevice.address}`);
    } catch (e) {
      console.error("[DEBUG] reconnect error:", e);
      toastError(`重连失败: ${e}`);
    } finally {
      reconnecting = false;
    }
  }

  function selectDevice(dev: ScanResult) {
    selectedDevice = dev;
    connectError = "";
  }

  async function confirmConnect() {
    if (!selectedDevice) return;
    const deviceLabel = selectedDevice.name || selectedDevice.address;
    try {
      await invoke("connect_device", {
        address: selectedDevice.address,
        name: selectedDevice.name || selectedDevice.address,
      });
      // 连接成功才关闭弹窗
      showDevicePicker = false;
      toastSuccess(`已连接到 ${deviceLabel}`);
    } catch (e) {
      // 连接失败:保留弹窗 + 显示错误 + 在弹窗里高亮错误信息
      connectError = String(e);
      toastError(`连接失败: ${e}`);
      console.error("[BLE] connect failed:", e);
    }
  }

  function cancelConnect() {
    showDevicePicker = false;
  }

  async function onBleDriver() {
    try {
      await invoke("force_cleanup_ble");
      toastInfo("BLE 驱动已重启");
    } catch (e) {
      toastError(`BLE 操作失败: ${e}`);
    }
  }

  function onConfigMode() {
    if (unsavedCount > 0) {
      toastWarning(`有 ${unsavedCount} 项未保存的修改`);
    } else {
      toastInfo("已切换到键盘控制模式");
    }
  }

  // ====================== 菜单项处理 ======================

  function onMenu(e: CustomEvent<{ action: string }>) {
    const { action } = e.detail;
    switch (action) {
      case "restore-defaults":
        activeModal.set("restore-defaults");
        break;
      case "reconnect":
        activeModal.set("reconnect");
        break;
      case "clear-oled":
        activeModal.set("clear-oled");
        break;
      case "device-info":
        activeModal.set("device-info");
        break;
      case "version-info":
        activeModal.set("version-info");
        break;
      case "language":
        activeModal.set("language");
        break;
      case "exit":
        activeModal.set("exit");
        break;
      case "about-rust":
        activeModal.set("version-info");
        break;
    }
  }

  // ====================== InspectorPane 回调 ======================

  function onSimulateKey() {
    toastSuccess(`已模拟按键 K${selectedKeyId}`);
  }

  function onApplyConfig() {
    unsavedCount = 0;
    toastSuccess("配置已应用到设备");
  }

  function onResetDefaults() {
    unsavedCount = 0;
    toastInfo("已恢复默认配置");
  }
</script>

<main>
  {#if state}
    <TopBar
      connected={state.connection.connected}
      deviceName={state.device.device_name}
      batteryLevel={state.device.battery_level}
      switchTitle={state.switch_title || "手动批准"}
      on:toggleConnect={onToggleConnect}
      on:bleDriver={onBleDriver}
      on:configMode={onConfigMode}
      on:menu={onMenu}
    />

    <div class="main-area">
      <div class="canvas-wrap">
        <div class="mode-header">
          <span class="section-title">键盘模式</span>
          <div class="mode-picker">
            {#each modeSlots as slot}
              <button
                class="mode-toggle"
                class:selected={selectedMode === slot.id}
                on:click={() => onModeChange(new CustomEvent('modechange', { detail: slot.id }))}
              >
                {slot.name}
              </button>
            {/each}
          </div>
        </div>

        <CanvasPane
          keys={keys}
          selectedKeyId={selectedKeyId}
          lightSegments={lightSegments}
          on:keyclick={onKeyClick}
        />
      </div>

      <InspectorPane
        selectedKeyId={selectedKeyId}
        selectedKey={keys.find((k) => k.id === selectedKeyId)}
        mode={selectedMode}
        modeName={modeSlots[selectedMode]?.name ?? ""}
        on:simulate={onSimulateKey}
        on:apply={onApplyConfig}
        on:reset={onResetDefaults}
      />
    </div>

    <StatusBar
      selectedPart="Key 1 · 快捷键"
      deviceName={state.device.device_name || "待保存"}
      dirtyCount={unsavedCount}
    />
  {:else}
    <div class="loading">{loadingMsg}</div>
  {/if}
</main>

{#if showDevicePicker}
  <div class="picker-overlay" on:click={cancelConnect}>
    <div class="picker-panel" on:click|stopPropagation>
      <div class="picker-header">
        <span class="picker-title">选择 BLE 设备</span>
        <button class="picker-close" on:click={cancelConnect}>✕</button>
      </div>

      {#if scanning}
        <div class="picker-loading">
          <div class="spinner"></div>
          <span>正在扫描 BLE 设备...</span>
        </div>
      {:else if scanResults.length === 0}
        <div class="picker-tips">
          <strong>⚠️ AhaKey 当前可能已通过蓝牙键盘通道连接 Windows</strong>
          <p>在这种情况下,AhaKey 不广播 BLE,应用无法连接。</p>
          <p class="tip-step">① 打开 <kbd>Windows 设置 → 蓝牙 → AhaKey 5A93</kbd></p>
          <p class="tip-step">② 点 <kbd>断开</kbd> (不是"移除")</p>
          <p class="tip-step">③ 立即回到这里点 <kbd>重新扫描</kbd></p>
          <p class="tip-step">④ AhaKey 进入广播状态 → 应用自动连接</p>
        </div>
      {:else}
        <div class="picker-list">
          {#each sortedResults as dev, i (dev.address)}
            <button
              class="picker-item"
              class:selected={selectedDevice?.address === dev.address}
              on:click={() => selectDevice(dev)}
            >
              <div class="picker-item-info">
                <span class="picker-item-name">
                  {dev.name || "(无名称)"}
                  {#if dev.matched_ahakey || dev.name.toLowerCase().includes('ahakey')}
                    <span class="badge badge-ahakey">AhaKey</span>
                  {/if}
                  {#if i === 0 && dev.rssi > -70}
                    <span class="badge badge-closest">最接近</span>
                  {/if}
                </span>
                <span class="picker-item-addr">{dev.address}</span>
              </div>
              <div class="picker-item-rssi">
                {#if dev.rssi > -60}
                  <span class="rssi-strong">●●●</span>
                {:else if dev.rssi > -80}
                  <span class="rssi-medium">●●○</span>
                {:else}
                  <span class="rssi-weak">●○○</span>
                {/if}
                <span class="rssi-db">{dev.rssi}dBm</span>
              </div>
            </button>
          {/each}
        </div>
      {/if}

      {#if connectError}
        <div class="picker-error">
          <span class="picker-error-icon">⚠️</span>
          <div class="picker-error-text">{connectError}</div>
          <button class="picker-error-dismiss" on:click={() => connectError = ""}>✕</button>
        </div>
      {/if}

      <div class="picker-footer">
        <button class="picker-btn-secondary" on:click={startScan} disabled={scanning}>
          {scanning ? "扫描中..." : "重新扫描"}
        </button>
        {#if lastDevice}
          <button
            class="picker-btn-reconnect"
            on:click={reconnectLastDevice}
            disabled={reconnecting}
            title="跳过扫描,直接连接上次设备 {lastDevice.address}"
          >
            {reconnecting ? "重连中..." : `重连 ${lastDevice.name || lastDevice.address}`}
          </button>
        {/if}
        <button
          class="picker-btn-primary"
          disabled={!selectedDevice || scanning}
          on:click={confirmConnect}
        >
          连接
        </button>
      </div>
    </div>
  </div>
{/if}

<Toast />
<Modal />

<style>
  main {
    display: flex;
    flex-direction: column;
    height: 100vh;
  }
  .main-area {
    display: flex;
    flex: 1;
    overflow: hidden;
    align-items: stretch;
    padding: 16px 20px;
    gap: 16px;
    background: var(--bg-primary);
  }
  .canvas-wrap {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 14px;
    min-width: 0;
  }
  .mode-header {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 0 4px;
  }
  .loading {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100vh;
    color: var(--text-secondary);
    font-size: 14px;
  }

  /* 设备选择器弹窗 */
  .picker-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.45);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 2000;
  }
  .picker-panel {
    background: #fff;
    border-radius: 14px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.25);
    width: 440px;
    max-height: 520px;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  .picker-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 16px 20px;
    border-bottom: 1px solid #f0f0f3;
  }
  .picker-title {
    font-size: 16px;
    font-weight: 600;
    color: #1d1d1f;
  }
  .picker-close {
    background: transparent;
    border: 0;
    font-size: 16px;
    color: #86868b;
    cursor: pointer;
    padding: 4px 8px;
  }
  .picker-close:hover {
    color: #1d1d1f;
  }
  .picker-loading {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    padding: 48px 20px;
    color: #86868b;
    font-size: 14px;
  }
  .spinner {
    width: 32px;
    height: 32px;
    border: 3px solid #e8e8ed;
    border-top-color: #0a84ff;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }
  @keyframes spin {
    to { transform: rotate(360deg); }
  }
  .picker-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 40px 20px;
    color: #86868b;
  }
  .picker-empty p {
    margin: 0;
    font-size: 14px;
  }
  .picker-empty .hint {
    font-size: 12px;
    color: #aeaeb2;
  }
  .picker-tips {
    padding: 16px 20px;
    background: #fff8e1;
    border-radius: 8px;
    margin: 16px;
    border-left: 4px solid #ff9500;
    font-size: 13px;
    line-height: 1.6;
    color: #4a4a4a;
  }
  .picker-tips strong {
    display: block;
    margin-bottom: 8px;
    color: #d97700;
    font-size: 14px;
  }
  .picker-tips p {
    margin: 4px 0;
  }
  .picker-tips .tip-step {
    font-size: 12px;
    color: #5a5a5a;
  }
  .picker-tips kbd {
    background: #fff;
    border: 1px solid #d0d0d0;
    border-radius: 3px;
    padding: 1px 5px;
    font-family: monospace;
    font-size: 11px;
    color: #333;
  }
  .picker-list {
    flex: 1;
    overflow-y: auto;
    padding: 8px;
  }
  .picker-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    padding: 12px 14px;
    background: #fafafa;
    border: 2px solid transparent;
    border-radius: 10px;
    cursor: pointer;
    text-align: left;
    transition: all 0.15s ease;
    font-family: inherit;
  }
  .picker-item:hover {
    background: #f0f0f3;
  }
  .picker-item.selected {
    border-color: #0a84ff;
    background: #e8f1ff;
  }
  .picker-item-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }
  .picker-item-name {
    font-size: 14px;
    font-weight: 500;
    color: #1d1d1f;
  }
  .picker-item-addr {
    font-size: 12px;
    color: #86868b;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  }
  .picker-item-rssi {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    gap: 2px;
    flex-shrink: 0;
    margin-left: 12px;
  }
  .picker-item-rssi .rssi-strong { color: #30d158; font-size: 14px; letter-spacing: 1px; }
  .picker-item-rssi .rssi-medium { color: #ffd60a; font-size: 14px; letter-spacing: 1px; }
  .picker-item-rssi .rssi-weak { color: #ff3b30; font-size: 14px; letter-spacing: 1px; }
  .picker-item-rssi .rssi-db { font-size: 11px; color: #86868b; }
  .badge {
    display: inline-block;
    padding: 1px 6px;
    border-radius: 4px;
    font-size: 10px;
    font-weight: 600;
    margin-left: 6px;
    vertical-align: middle;
  }
  .badge-ahakey {
    background: #e8f1ff;
    color: #0a84ff;
  }
  .badge-closest {
    background: #fff3e0;
    color: #ff9500;
  }
  .picker-footer {
    display: flex;
    gap: 10px;
    padding: 14px 20px;
    border-top: 1px solid #f0f0f3;
  }
  .picker-error {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    margin: 0 20px 8px;
    padding: 10px 12px;
    background: #fff5f5;
    border: 1px solid #ffcccc;
    border-radius: 8px;
    color: #c62828;
    font-size: 12px;
    line-height: 1.5;
  }
  .picker-error-icon {
    flex-shrink: 0;
  }
  .picker-error-text {
    flex: 1;
    word-break: break-word;
  }
  .picker-error-dismiss {
    flex-shrink: 0;
    border: none;
    background: transparent;
    color: #c62828;
    cursor: pointer;
    font-size: 14px;
    padding: 0 4px;
  }
  .picker-btn-primary {
    flex: 1;
    padding: 10px 20px;
    background: #0a84ff;
    color: #fff;
    border: 0;
    border-radius: 10px;
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
    font-family: inherit;
  }
  .picker-btn-primary:hover:not(:disabled) {
    background: #0070e0;
  }
  .picker-btn-primary:disabled {
    background: #c7c7cc;
    cursor: not-allowed;
  }
  .picker-btn-secondary {
    padding: 10px 20px;
    background: #f0f0f3;
    color: #1d1d1f;
    border: 0;
    border-radius: 10px;
    font-size: 14px;
    font-weight: 500;
    cursor: pointer;
    font-family: inherit;
  }
  .picker-btn-secondary:hover:not(:disabled) {
    background: #e5e5ea;
  }
  .picker-btn-reconnect {
    padding: 10px 16px;
    background: #fff3e0;
    color: #ff9500;
    border: 1px solid #ffd180;
    border-radius: 10px;
    font-size: 14px;
    font-weight: 500;
    cursor: pointer;
    font-family: inherit;
    white-space: nowrap;
    max-width: 180px;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .picker-btn-reconnect:hover:not(:disabled) {
    background: #ffe0b2;
  }
  .picker-btn-reconnect:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  .picker-btn-secondary:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>

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

  // 连接状态
  // v2 bridge 链路下设备永远只有 1 个(从 config_store 读 last_device),不再需要弹窗
  let connecting = false;            // 连接中 — 显示 loading 状态避免重复点击
  let lastDevice: LastDevice | null = null;

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

  async function onModeChange(e: CustomEvent<number>) {
    const newMode = e.detail;
    selectedMode = newMode;
    unsavedCount += 1;
    toastInfo(`已切换到 ${modeSlots[newMode]?.name}`);
    // 必须通知后端,否则下个 device-status-changed 事件会用 state.active_mode(0)覆盖 selectedMode
    try {
      await invoke("set_active_mode", { mode: newMode });
    } catch (e) {
      console.error("[MODE] set_active_mode failed:", e);
      toastError(`切换 mode 失败: ${e}`);
    }
  }

  function onKeyClick(e: CustomEvent<number>) {
    selectedKeyId = e.detail;
  }

  // ====================== 顶部按钮 ======================

  /// 直接连接 v2 bridge(无弹窗)
  /// 设备从 config_store 读 last_device(必须先在 Windows 蓝牙手动配对一次)
  async function connectToBridge() {
    if (connecting) return;
    connecting = true;
    try {
      // 读最新 last_device(可能刚被前次连接保存)
      if (!lastDevice) {
        lastDevice = await invoke<LastDevice | null>("get_last_device");
      }
      if (!lastDevice) {
        toastWarning("未找到上次连接的设备,请先在 Windows 蓝牙配对 AhaKey 后重启应用");
        return;
      }
      const deviceLabel = lastDevice.name || lastDevice.address;
      toastInfo(`正在连接 ${deviceLabel}...`);
      // 客户端兜底 15s timeout:后端 v2 bridge 拨号 + GATT 订阅 + 启动 1s 轮询
      const timeoutMs = 15000;
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error(`连接超时(${timeoutMs / 1000}s),后端可能在重试 BLE — 看 ahakey-test.log.err`)), timeoutMs);
      });
      await Promise.race([
        invoke("connect_device", {
          address: lastDevice.address,
          name: deviceLabel,
        }),
        timeoutPromise,
      ]);
      toastSuccess(`已连接到 ${deviceLabel}`);
    } catch (e) {
      toastError(`连接失败: ${e}`);
      console.error("[BLE] connect failed:", e);
    } finally {
      connecting = false;
    }
  }

  async function onToggleConnect() {
    console.log("[DEBUG] onToggleConnect clicked, state=", state);
    if (state?.connection.connected) {
      try {
        await invoke("disconnect_device");
        toastInfo("已断开连接");
      } catch (e) {
        console.error("[DEBUG] disconnect error:", e);
        toastError(`断开失败: ${e}`);
      }
    } else {
      // 直接连 v2 bridge — 无弹窗
      await connectToBridge();
    }
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
      connecting={connecting}
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
          switchTitle={state.switch_title}
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
</style>

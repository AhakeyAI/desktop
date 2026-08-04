<script lang="ts">
  import { createEventDispatcher } from "svelte";

  /// 跟 App.svelte 的 StudioPart 同名
  type StudioPart = 'lightBar' | 'oledDisplay' | 'key1' | 'key2' | 'key3' | 'key4' | 'toggleSwitch';

  export let keys: Array<{ id: number; label: string; name: string }> = [];
  export let selectedPart: StudioPart = 'key1';
  /// 4 段灯条(对齐 win-java 4 段)
  export let lightSegments: number[] = [0, 1, 2, 3];
  /// 旋钮 label(由 App.svelte 从 state.switch_title 传)
  export let switchTitle: string = "";
  /// 当前 mode(0-3)— 显示在右下角 modeBadge
  export let modeIndex: number = 0;

  const dispatch = createEventDispatcher();

  function selectPart(part: StudioPart) {
    // 不直接改 prop(只读),只 dispatch 让父组件改
    dispatch("selectPart", part);
  }

  /// K1-K4:用 key.id 拼成 'key1' / 'key2' 等
  function keyPart(keyId: number): StudioPart {
    return `key${keyId}` as StudioPart;
  }

  /// win-java: deviceStatus.isAutoApproval() → translateY -13(上=auto), +13(下=manual)
  /// 简化:用 switchTitle 文本判断("自动批准" = auto → thumb 在上)
  $: thumbUp = switchTitle.includes("自动");
  $: thumbOffset = thumbUp ? "-13px" : "13px";

  /// mode badge: 1-based index
  $: modeLabel = String(modeIndex + 1);
</script>

<div class="keyboard-stage">
  <!-- 左栏:灯条 + 4 键 -->
  <div class="left-col">
    <!-- 灯条 hotspot -->
    <button
      type="button"
      class="hotspot light-bar-card"
      class:selected={selectedPart === 'lightBar'}
      on:click={() => selectPart('lightBar')}
    >
      <div class="light-bar-inner">
        <div class="hotspot-label">灯条</div>
        <div class="light-bar-track">
          {#each lightSegments as _}
            <div class="light-segment"></div>
          {/each}
        </div>
      </div>
    </button>

    <!-- 4 键 hotspots -->
    <div class="keys-container">
      <div class="keys-row">
        {#each keys as key}
          <button
            type="button"
            class="hotspot key-card"
            class:selected={selectedPart === keyPart(key.id)}
            on:click={() => selectPart(keyPart(key.id))}
          >
            <div class="key-glyph">{key.label}</div>
            <div class="key-caption">{key.name}</div>
          </button>
        {/each}
      </div>
    </div>
  </div>

  <!-- 右栏:OLED + 旋钮 + mode badge -->
  <div class="right-col">
    <!-- OLED hotspot -->
    <button
      type="button"
      class="hotspot oled-card"
      class:selected={selectedPart === 'oledDisplay'}
      on:click={() => selectPart('oledDisplay')}
    >
      <div class="oled-screen">
        <div class="oled-title">未选择</div>
        <div class="oled-caption">等待选择 GIF / 图片</div>
      </div>
    </button>

    <!-- 旋钮 hotspot -->
    <button
      type="button"
      class="hotspot toggle-card"
      class:selected={selectedPart === 'toggleSwitch'}
      on:click={() => selectPart('toggleSwitch')}
    >
      <div class="toggle-inner">
        <div class="toggle-assembly">
          <div class="toggle-rail"></div>
          <div class="toggle-thumb" style="transform: translateY({thumbOffset});"></div>
        </div>
        <div class="hotspot-label">{switchTitle || "手动批准"}</div>
      </div>
    </button>

    <!-- mode badge:只读,不可点 -->
    <div class="mode-badge">
      <div class="mode-icon">{modeLabel}</div>
    </div>
  </div>
</div>

<style>
  .keyboard-stage {
    display: flex;
    gap: 24px;
    width: 100%;
    height: 100%;
  }

  .left-col {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 20px;
    min-width: 0;
  }

  .right-col {
    display: flex;
    flex-direction: column;
    gap: 16px;
    align-items: flex-end;
  }

  /* 通用 hotspot:卡片样式 + 选中蓝边 + dirty 标记(预留) */
  .hotspot {
    background: #fff;
    border: 2px solid transparent;
    border-radius: 14px;
    cursor: pointer;
    font-family: inherit;
    text-align: left;
    padding: 0;
    transition: border-color 0.15s ease, box-shadow 0.15s ease, transform 0.05s ease;
  }
  .hotspot:hover {
    border-color: #d0d0d6;
  }
  .hotspot.selected {
    border-color: #0a84ff;
    box-shadow: 0 0 0 3px rgba(10, 132, 255, 0.15);
  }
  .hotspot.dirty {
    box-shadow: 0 0 0 2px #ff9f0a inset;
  }
  .hotspot:active {
    transform: scale(0.99);
  }

  .hotspot-label {
    font-size: 13px;
    font-weight: 500;
    color: #1d1d1f;
  }

  /* 灯条 hotspot */
  .light-bar-card {
    padding: 14px 20px;
  }
  .light-bar-inner {
    display: flex;
    flex-direction: column;
    gap: 10px;
    align-items: stretch;
  }
  .light-bar-track {
    display: flex;
    gap: 14px;
    justify-content: center;
    align-items: center;
  }
  .light-segment {
    width: 32px;
    height: 12px;
    border-radius: 999px;
    background: linear-gradient(180deg, #5ac8fa 0%, #0a84ff 100%);
    box-shadow: 0 0 6px rgba(90, 200, 250, 0.6);
    opacity: 0.85;
  }

  /* 4 键 hotspots */
  .keys-container {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    background: #fff;
    border-radius: 14px;
    padding: 24px;
    min-height: 200px;
  }
  .keys-row {
    display: flex;
    gap: 14px;
  }
  .key-card {
    width: 96px;
    height: 96px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 6px;
    background: #fafafa;
    border-radius: 14px;
  }
  .key-glyph {
    font-size: 18px;
    font-weight: 600;
    color: #1d1d1f;
  }
  .key-caption {
    font-size: 11px;
    color: #86868b;
  }

  /* OLED hotspot */
  .oled-card {
    width: 200px;
    padding: 0;
  }
  .oled-screen {
    background: rgba(20, 20, 25, 0.92);
    border-radius: 12px;
    padding: 18px 12px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 4px;
    min-height: 100px;
  }
  .oled-title {
    color: #5ac8fa;
    font-size: 13px;
    font-weight: 500;
  }
  .oled-caption {
    color: #86868b;
    font-size: 11px;
  }

  /* 旋钮 hotspot */
  .toggle-card {
    width: 110px;
    padding: 14px;
  }
  .toggle-inner {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
  }
  .toggle-assembly {
    position: relative;
    width: 36px;
    height: 80px;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .toggle-rail {
    position: absolute;
    width: 18px;
    height: 56px;
    background: #e5e5ea;
    border-radius: 12px;
  }
  .toggle-thumb {
    position: absolute;
    width: 34px;
    height: 24px;
    background: linear-gradient(180deg, #fafafa, #d1d1d6);
    border-radius: 12px;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.15);
    transition: transform 0.25s ease;
  }

  /* mode badge:只读,显示当前 mode (1-based) */
  .mode-badge {
    width: 56px;
    height: 56px;
    border-radius: 50%;
    background: linear-gradient(135deg, #0a84ff 0%, #5e5ce6 100%);
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 4px 12px rgba(10, 132, 255, 0.3);
  }
  .mode-icon {
    color: #fff;
    font-size: 22px;
    font-weight: 700;
  }
</style>

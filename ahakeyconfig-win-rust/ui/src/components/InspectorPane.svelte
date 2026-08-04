<script lang="ts">
  import { createEventDispatcher } from "svelte";

  /// 跟 App.svelte 的 StudioPart 同名
  type StudioPart = 'lightBar' | 'oledDisplay' | 'key1' | 'key2' | 'key3' | 'key4' | 'toggleSwitch';

  export let selectedPart: StudioPart = 'key1';
  export let mode: number = 0;
  export let modeName: string = "Claude";

  const dispatch = createEventDispatcher();

  $: partTitle = {
    'lightBar': '灯条',
    'oledDisplay': 'OLED 屏幕',
    'key1': 'Key 1 · 快捷键',
    'key2': 'Key 2 · 快捷键',
    'key3': 'Key 3 · 快捷键',
    'key4': 'Key 4 · 快捷键',
    'toggleSwitch': '旋钮开关',
  }[selectedPart];

  $: isKey = selectedPart === 'key1' || selectedPart === 'key2' || selectedPart === 'key3' || selectedPart === 'key4';
  $: keyNumber = selectedPart === 'key1' ? 1 : selectedPart === 'key2' ? 2 : selectedPart === 'key3' ? 3 : 4;

  function simulateKey() {
    dispatch("simulate");
  }
  function applyConfig() {
    dispatch("apply");
  }
  function resetDefaults() {
    dispatch("reset");
  }
</script>

<aside class="inspector-pane">
  <div class="inspector-header">
    <span class="inspector-icon">⌨</span>
    <h2 class="inspector-title">{partTitle}</h2>
  </div>
  <div class="inspector-subtitle">{modeName} · 模式 {mode + 1}</div>

  {#if selectedPart === 'lightBar'}
    <!-- 灯条 group:2B 实现颜色/亮度/灯效 -->
    <div class="group-box placeholder-box">
      <div class="group-label">灯条</div>
      <p class="placeholder">灯条灯效配置(颜色/亮度/灯效选择)— 待 2B 实现</p>
    </div>

  {:else if selectedPart === 'oledDisplay'}
    <!-- OLED group:2B 实现文件上传 + 预览 -->
    <div class="group-box placeholder-box">
      <div class="group-label">OLED 屏幕</div>
      <p class="placeholder">图片/GIF 上传(选文件 → 推送到设备)— 待 2B 实现</p>
    </div>

  {:else if selectedPart === 'toggleSwitch'}
    <!-- 旋钮 group:只读档位说明 -->
    <div class="group-box placeholder-box">
      <div class="group-label">旋钮开关</div>
      <p class="placeholder">物理档位说明(只读 — 由硬件拨杆决定)— 待 2B 完善文案</p>
    </div>

  {:else if isKey}
    <!-- K1-K4:键位配置 group — 保留 2A 现有内容 -->
    <div class="group-box">
      <div class="group-label">将写入键盘的按键绑定</div>

      <div class="field-label">按钮类型</div>
      <select>
        <option>快捷键</option>
        <option>宏</option>
        <option>系统命令</option>
      </select>

      <div class="field-label" style="margin-top: 16px;">键码列表(修饰键在前,普通键在后)</div>
      <div class="key-list">
        <div class="key-list-item">
          <span>Left Ctrl (0xE0)</span>
          <button class="link-btn">删除</button>
        </div>
      </div>

      <div class="add-row">
        <input class="text-field" placeholder="修饰键" />
        <span class="plus">+</span>
        <input class="text-field code-input" placeholder="0x00" />
        <button class="button-action">添加</button>
        <button class="button-action">修改</button>
      </div>
    </div>

    {#if selectedPart === 'key1'}
      <!-- K1 专属:模拟按键按钮 -->
      <div class="group-box">
        <div class="group-label">模拟按键</div>
        <button class="button-prominent" on:click={simulateKey}>
          模拟按一次 Key {keyNumber}
        </button>
      </div>
    {/if}

    <div class="group-box">
      <div class="group-label">按键描述</div>
      <input class="text-field" type="text" placeholder="Record" />

      <div class="action-row" style="margin-top: 14px;">
        <button class="button-prominent" on:click={applyConfig}>应用到设备</button>
        <button class="button-action" on:click={resetDefaults}>恢复默认</button>
      </div>
    </div>
  {/if}
</aside>

<style>
  .placeholder-box {
    background: linear-gradient(180deg, #fafafa 0%, #f5f5f7 100%);
    border: 1px dashed #d0d0d6;
  }
  .placeholder {
    margin: 8px 0 0;
    font-size: 13px;
    color: #86868b;
    line-height: 1.5;
  }
  .action-row {
    display: flex;
    gap: 8px;
  }
  .action-row .button-prominent { flex: 1; }
</style>

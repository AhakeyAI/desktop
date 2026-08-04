<script lang="ts">
  import { createEventDispatcher } from "svelte";

  export let selectedKeyId: number = 1;
  export let selectedKey: { id: number; label: string; name: string } | undefined = undefined;
  export let mode: number = 0;
  export let modeName: string = "Claude";

  const dispatch = createEventDispatcher();

  let keyBindings: Array<{ key: string; code: string }> = [
    { key: "Left Ctrl", code: "0xE0" },
  ];

  let newKey = "";
  let newCode = "0x";

  function addBinding() {
    if (newKey && newCode) {
      keyBindings = [...keyBindings, { key: newKey, code: newCode }];
      newKey = "";
      newCode = "0x";
    }
  }

  function removeBinding(i: number) {
    keyBindings = keyBindings.filter((_, idx) => idx !== i);
  }

  function simulateKey() {
    dispatch("simulate");
  }

  function applyConfig() {
    dispatch("apply");
  }

  function resetDefaults() {
    dispatch("reset");
  }

  let description = "Record";
</script>

<aside class="inspector-pane">
  <div class="inspector-header">
    <span class="inspector-icon">⌨</span>
    <h2 class="inspector-title">Key {selectedKeyId} · 快捷键</h2>
  </div>
  <div class="inspector-subtitle">{modeName}</div>

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
      {#each keyBindings as binding, i}
        <div class="key-list-item">
          <span>{binding.key} ({binding.code})</span>
          <button class="link-btn" on:click={() => removeBinding(i)}>删除</button>
        </div>
      {/each}
    </div>

    <div class="add-row">
      <input class="text-field" bind:value={newKey} placeholder="修饰键" />
      <span class="plus">+</span>
      <input class="text-field code-input" bind:value={newCode} placeholder="0x00" />
      <button class="button-action" on:click={addBinding}>添加</button>
      <button class="button-action">修改</button>
    </div>
  </div>

  <div class="group-box">
    <div class="group-label">模拟按键</div>
    <button class="button-prominent" on:click={simulateKey}>
      模拟按一次 Key {selectedKeyId}
    </button>
  </div>

  <div class="group-box">
    <div class="group-label">按键描述</div>
    <input class="text-field" type="text" bind:value={description} />

    <div class="action-row" style="margin-top: 14px;">
      <button class="button-prominent" on:click={applyConfig}>应用到设备</button>
      <button class="button-action" on:click={resetDefaults}>恢复默认</button>
    </div>
  </div>
</aside>

<style>
  .action-row {
    display: flex;
    gap: 8px;
  }
  .action-row .button-prominent { flex: 1; }
</style>

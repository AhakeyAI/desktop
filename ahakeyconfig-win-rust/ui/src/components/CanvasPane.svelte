<script lang="ts">
  import { createEventDispatcher } from "svelte";

  export let keys: Array<{ id: number; label: string; name: string }> = [];
  export let selectedKeyId: number = 1;
  export let lightSegments: number[] = [];
  export let switchTitle: string = "";

  const dispatch = createEventDispatcher();

  function selectKey(id: number) {
    dispatch("keyclick", id);
  }
</script>

<div class="key-preview">
  <div class="kb-stage">
    <!-- 灯条区 -->
    <div class="light-row">
      <div class="light-label">灯条</div>
      <div class="light-bar-track">
        {#each lightSegments as _}
          <div class="light-segment"></div>
        {/each}
      </div>
    </div>

    <!-- 主舞台:左 K1-K4,右侧 GIF + 旋钮 -->
    <div class="stage-main">
      <div class="keys-area">
        {#each keys as key}
          <div
            class="key-card"
            class:selected-key={selectedKeyId === key.id}
            on:click={() => selectKey(key.id)}
            on:keypress={(e) => e.key === 'Enter' && selectKey(key.id)}
            role="button"
            tabindex="0"
          >
            <div class="key-glyph">{key.label}</div>
            <div class="key-caption">{key.name}</div>
          </div>
        {/each}
      </div>

      <div class="right-area">
        <div class="gif-preview">
          <div class="gif-text">未选择</div>
          <div class="gif-sub">等待选择 GIF / 图片</div>
        </div>

        <div class="knob-wrap">
          <div class="knob-switch">
            <div class="knob-handle"></div>
          </div>
          <div class="knob-label">{switchTitle || "手动批准"}</div>
          <div class="knob-num-circle">
            <span>1</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
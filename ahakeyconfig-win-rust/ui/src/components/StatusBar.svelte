<script lang="ts">
  export let selectedPart: string = "Key 1 · 快捷键";
  export let deviceName: string = "待保存";
  export let dirtyCount: number = 0;
</script>

<div class="status-bar">
  <span>当要选: {selectedPart}</span>
  <span>设备: {deviceName}</span>
  <span>待保存改动: {dirtyCount}</span>
  <div class="spacer"></div>
  <span>修改会先存在本地,保存配置后写入键盘, 尚未保存</span>
</div>

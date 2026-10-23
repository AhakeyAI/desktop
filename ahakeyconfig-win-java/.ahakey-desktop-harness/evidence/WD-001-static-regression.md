# WD-001 Static Regression Evidence

Role: DIB

Checks:

1. Sleep wait time protocol path:
   - `AhaKeyProtocol` adds `CMD_SLEEP_WAIT_TIME = 0x95`.
   - `AhaKeyProtocol.querySleepWaitTime()` builds `AA BB 95 CC DD`.
   - `AhaKeyProtocol.setSleepWaitTime(minutes)` only accepts `0/30/60/120` and writes little-endian uint16 payload.
   - `BleManager.setSleepWaitTimeMinutesAndVerify()` sends `0x95` set, waits for `0x95`, then sends `0x95` query and verifies readback.

2. No `0x04 save_config` dependency for this feature:
   - Static search found `CMD_SAVE_CONFIG` and `saveConfig()` only as pre-existing generic protocol code in `AhaKeyProtocol`.
   - The new sleep wait time methods do not call `saveConfig()` or `CMD_SAVE_CONFIG`.

3. UI placement:
   - `TopBar.showDeviceInfoDialog()` now creates `sleepWaitTimeControl`.
   - The control is added with `deviceCard.getChildren().addAll(deviceTitle, deviceRow1, deviceRow2, sleepWaitTimeControl)`.
   - `content.getChildren().addAll(deviceCard, claudeCard, cursorCard, codexCard, kimiCard, logCard, actionButtons)` is unchanged in shape; no separate sleep card was added.

4. User-visible states:
   - Not connected: `请先连接键盘`.
   - Reading/saving busy states disable the control.
   - Unsupported readback value: `当前值异常，请重新保存`.
   - Save failure and read failure show explicit messages.

Result: PASS for static code-level regression. Real device and Owner UAT remain pending.

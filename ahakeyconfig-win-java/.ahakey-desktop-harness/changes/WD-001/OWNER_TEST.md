# WD-001 Owner Test — CP3A 睡眠等待时间 Windows 联调

本测试包只覆盖 WD-001 已批准范围：Windows 端在 More / Hawk 安装分发工具 / 第一个“设备信息”卡片内配置 CP3A “睡眠等待时间”，并通过 `0x95 set -> 0x95 OK -> 0x95 query -> readback match` 验证。它不代表官网发布、全产品回归或旧固件兼容已完成。

## Windows 测试版本

- Git candidate: `666494c358fd5373b27b6213e9f4a35a424dd2c6`
- Build receipt: `.ahakey-desktop-harness/changes/WD-001/BUILD_RECEIPT.json`
- Build log: `.ahakey-desktop-harness/evidence/WD-001-build-package-20260929T031933Z.log`
- Artifact: `target/ahakey-studio-1.0.0.jar`
- Artifact SHA256: `C16F5BAD0F518FB8FEA00F7DEE7F97CAAF7AC6DC3865092442A2BEE260217886`
- Runtime dependencies: `target/lib` with 17 dependency JARs
- Main class from manifest: `com.example.ahakey.App`

This package was built with temporary JDK 17 and `mvn.cmd "-DskipTests" package`. That proves packaging completed; it does not prove app launch, UI behavior, device behavior, or Owner UAT.

## Launch Steps

Open PowerShell in:

```powershell
cd "C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java"
$env:JAVA_HOME="D:\jdk-17.0.19.10-hotspot"
$env:Path="$env:JAVA_HOME\bin;$env:Path"
java -version
java -jar ".\target\ahakey-studio-1.0.0.jar"
```

Expected launch result:

- Java reports version `17.0.19` from `D:\jdk-17.0.19.10-hotspot`.
- AhaKey Studio opens normally.
- No automatic device write occurs merely from launch.
- If launch fails, return the full PowerShell output and `logs\ahakey-studio.log` from the same working directory.

## Firmware And Device Preconditions

Firmware candidate for this test:

- Hardware/checkpoint: X1 / CP3A
- Firmware commit: `a9db65e2e73bc56b669c312e9fc42f3ee02c3d49`
- Firmware HEX: `.ahakey-harness/evidence/builds/ws1-cp3a-host-configurable-quiet-sleep-timeout/HID_Keyboard_582m_vibe_coding.hex`
- HEX SHA256: `9AABCE5F015FD44D980FF6818D825B6BAB34F6E4B4F7AC277E942272D700444C`
- Gate evidence: CP3A candidate readiness `READY_FOR_REGATE`
- Protocol decision: `0x95` is self-persisting; Windows must not send `0x04 save_config` for this setting.

Owner must confirm before testing that the physical keyboard is the intended X1 / CP3A test unit and is flashed with the HEX above, or explicitly report the actual installed firmware identity. This handoff does not claim the device is already flashed.

Connection:

- Use the normal connection path supported by the current app and test unit.
- If BLE bridge/driver is needed, start it as you normally do for device tests; this handoff does not install or start drivers automatically.

## Device Writes And Recovery

This test writes the sleep wait time configuration on the keyboard. It should not rewrite key mappings, OLED data, lighting, voice settings, Hook settings, or unrelated configuration.

Recovery:

- Record the initial sleep wait time shown by the app before changing it.
- At the end, restore that initial value if you need the unit back in its original state.
- If the app reports save failure, read failure, mismatch, disconnect, or unsupported value, stop the failing subtest, keep the device powered, and return the screenshot plus `logs\ahakey-studio.log`.

## Test Steps

1. Start AhaKey Studio with the PowerShell steps above.
   Expected: the app opens; no device setting is changed simply by launching.

2. Connect the X1 / CP3A keyboard using the normal test connection.
   Expected: the app shows the keyboard as connected. If connection fails, return the visible error and logs; do not continue write tests.

3. Open More, then the “Hawk 安装分发工具” dialog, then look at the first “设备信息” card.
   Expected: the existing device information remains visible, and a “睡眠等待时间” row appears in that first card. No new card or separate settings page is required.

4. Observe the initial sleep wait time value.
   Expected: one of “永不”, “30 分钟”, “60 分钟”, or “120 分钟” is selected. If the current value is unsupported, the app should show a clear abnormal-current-value message and still allow selecting a legal value.

5. Set “30 分钟” and save.
   Expected: the app reports save success only after firmware returns `0x95 OK` and the follow-up `0x95` query reads back 30. The app must not require or ask for an additional `0x04 save_config`.

6. Power-cycle or reboot the keyboard, reconnect, and re-open the same device info card.
   Expected: sleep wait time still reads back as 30. This is the persistence check; readback before reboot alone is not enough to claim persistence.

7. Repeat set/save/readback for “永不”, “60 分钟”, and “120 分钟”.
   Expected: each legal value saves successfully and reads back exactly the selected value.

8. Check a necessary preserved behavior in the same dialog.
   Expected: connection status, battery/device name/lever fields, Hook/driver/log areas and existing More dialog behavior remain usable as before.

9. Disconnect the keyboard or test with no keyboard connected.
   Expected: the sleep wait time control is disabled or reports “请先连接键盘”; it must not claim save success while disconnected.

10. Optional protocol-tool negative test, only if Owner already has the normal firmware/protocol test tool available.
    Expected: sending an illegal `0x95` value returns a nonzero firmware error and does not change the previous value. Do not use the normal UI for illegal values; it intentionally exposes only legal options.

## Return To DLA

Please return:

- Whether the physical unit was confirmed as the X1 / CP3A test unit flashed with the listed HEX SHA256.
- The actual connection path used.
- Pass/fail for each numbered step.
- Screenshots for the More / device info card and any failure.
- `logs\ahakey-studio.log` if launch, connection, read, save, mismatch, disconnect, or persistence fails.
- If a step was not executed, mark it as not executed rather than pass.

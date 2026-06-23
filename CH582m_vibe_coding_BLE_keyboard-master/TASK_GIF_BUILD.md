# 任务状态双套 GIF 固件构建与测试

## 构建前提

本项目依赖 WCH CH583EVT SDK 和 MounRiver Studio。当前仓库不包含 SDK 或可复现的 macOS 命令行工具链。

1. 从 WCH 下载 CH583EVT SDK。
2. 把本目录放入 SDK 的 `EXAM/BLE` 下。
3. 用 MounRiver Studio 打开 `HID_Keyboard_582m_vibe_coding.wvproj`。
4. Clean 后 Build，产物为 `obj/HID_Keyboard_582m_vibe_coding.hex`。

## 烧录

键盘进入 CH582 ISP/BOOT 模式后，可使用工作区的脚本：

```zsh
scripts/flash-firmware.sh /absolute/path/to/HID_Keyboard_582m_vibe_coding.hex
```

脚本等待 USB ISP 设备；保持 BOOT/PB22 低电平后接通键盘电源，开始擦写后松开。

## 实机测试

1. 用新版客户端为 Mode 0 的套图 A / B 分别配置 SessionEnd GIF。
2. 给其中一个套图的 `PreToolUse` 或 `PermissionRequest` 配置不同 GIF，点击底部“写入设备”。
3. Agent 发送 `0x90` 状态，确认 LCD 立即切到对应 GIF，随后发 `SessionEnd` 确认回退图。
4. 在同一 Mode 双击电源键，确认 LCD 切换到另一套图；重启键盘后再次确认选择保持。
5. 未配置状态应依次回退到当前套图的 SessionEnd、套图 A、旧版 Mode 动画，不应黑屏。

## BLE 命令

- `0x84` 写任务槽。
- `0x85` 读任务槽。
- `0x86` 设置或读取活动套图。
- `0x90` 同时驱动灯效和 LCD 状态图。

完整格式见工作区 `docs/ble-protocol.md`。

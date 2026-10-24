# AhaKey macOS 上位机同步交接文档

日期：2026-06-08

本文档用于把 macOS 上位机同步到当前最新固件与 Windows 上位机能力。macOS 同事可基于 `AhaKey-desktop-main-anpx/platforms/macos` 目录继续开发。

## 1. 当前 macOS 目录判断

目录：

`C:\Users\20825\Desktop\vibe-code\AhaKey-desktop-main-anpx\platforms\macos`

结论：

1. 这是 macOS 上位机代码。它是 SwiftPM 工程，`Package.swift` 定义了两个可执行产物：
   - `AhaKeyConfig`：主 App。
   - `ahakeyconfig-agent`：Hook/Agent 辅助进程。
2. 代码使用 SwiftUI、CoreBluetooth、macOS Agent/Hook 逻辑，因此必须在 macOS + Xcode/Swift 工具链下编译。Windows 机器上不能完整编译和验证。
3. 当前目录不能确认可以直接打出完整 DMG。原因是 `Makefile` 调用 `./scripts/build.sh`，但当前 `scripts` 目录里没有 `build.sh`。目前只看到图标和 DMG 背景生成脚本：
   - `scripts/generate_icons.swift`
   - `scripts/generate_dmg_background.swift`
4. 如果只验证 Swift 代码是否能编译，Mac 同事可以先在 macOS 上执行：

```bash
cd platforms/macos
swift build -c release
swift build -c release --product ahakeyconfig-agent
```

5. 如果要打 DMG，需要补回或重写 `scripts/build.sh`，完成 `.app` 组装、资源复制、Agent 嵌入、签名，以及 DMG 生成。

## 2. 最新固件能力摘要

当前固件已经不是早期只支持 3 个模式和 BLE 单通道的版本。Mac 上位机需要按以下能力对齐。

### 2.1 工作模式

固件现在支持 4 个工作模式：

| 固件索引 | 用户显示 | 默认含义 |
|---:|---|---|
| 0 | Mode 1 / Claude | Claude |
| 1 | Mode 2 / Cursor | Cursor |
| 2 | Mode 3 / Codex | Codex |
| 3 | Mode 4 / N/A | N/A，开放给未来使用 |

注意：上位机 UI 面向用户时不要显示 Mode 0。用户看到的模式从 Mode 1 开始，但协议里仍然用 `0..3`。

### 2.2 默认按键

三种主要模式的第 4 个键已经改成 Backspace，对应 HID 键值也同步改了。Mac 软件里如果有默认文案、默认快捷键说明或屏幕上的四键名称，需要把原来的 Enter 改成 Backspace。

### 2.3 灯条亮度

固件默认灯条亮度已改成 35。

新增亮度协议：

```text
AA BB 85 [brightness] CC DD
```

说明：

- 命令：`0x85`
- `brightness`：建议上位机限制在 `1..100`
- 当前出厂默认值：`35`
- Windows 上位机已经有亮度设置与测试逻辑

### 2.4 AI 状态灯效

固件支持 9 个 AI 状态。Hook 只需要下发当前状态，固件根据“当前工作模式 + 当前 AI 状态”查表显示对应灯效。

状态顺序建议按 Claude/Codex 会话流程展示：

| 状态值 | 状态名 | 含义 |
|---:|---|---|
| 4 | Session Start | 会话启动 |
| 7 | User Prompt Submit | 用户提交输入 |
| 3 | Pre Tool Use | 准备执行工具 |
| 1 | Permission Request | 等待用户批准 |
| 2 | Post Tool Use | 工具执行完成 |
| 0 | Notification | 普通通知 |
| 6 | Task Completed | 任务完成 |
| 5 | Stop | AI 停止 |
| 8 | Session End | 会话结束 |

Hook 状态更新协议仍是：

```text
AA BB 90 [state] CC DD
```

说明：

- 命令：`0x90`
- `state`：上表里的状态值
- 固件侧负责按当前模式查对应灯效

### 2.5 每个模式每个 AI 状态的灯效表

新增灯效表配置协议：

```text
AA BB 84 [mode] [effect_state0] [effect_state1] ... [effect_state8] CC DD
```

说明：

- 命令：`0x84`
- `mode`：`0..3`
- 后面 9 个字节分别对应状态 `0..8` 的灯效编号
- Windows 上位机支持为每个模式的每个 AI 状态单独设置灯效
- Mac 上位机需要补齐这部分 UI 与保存逻辑

### 2.6 直接预览灯效

新增灯效预览协议：

```text
AA BB 91 [effect] CC DD
```

说明：

- 命令：`0x91`
- 用于上位机“测试灯效”按钮
- 不改变用户最终保存的配置，只让键盘立即显示某个灯效
- 预览时固件仍保留高优先级状态：蓝牙/HID 未连接蓝灯、蓝牙重置提示、关机提示等优先级高于普通灯效

### 2.7 上位机切换键盘当前模式

新增模式切换协议：

```text
AA BB 92 [mode] CC DD
```

说明：

- 命令：`0x92`
- `mode`：`0..3`
- 上位机切换某个模式时，应同步通知固件切到该模式
- 固件会显示该模式的四个按键名称，随后恢复该模式对应 OLED 动图/图片

### 2.8 OLED 图片/GIF 上传

当前外置 Flash 是 `PY25Q64HA-SUH-IT SOP8 208mil`，容量 64 Mbit，也就是 8 MB。

OLED 帧参数：

- OLED：160 x 80
- 单帧槽位大小：`28672` 字节
- 总槽位：约 `292` 帧
- 固件保留出厂/系统槽位：前 `10` 帧
- 4 个模式平分用户区后，每个模式最多 `70` 帧

用户上传分区建议：

| 模式 | mode 值 | 起始 slot | 最大帧数 |
|---|---:|---:|---:|
| Mode 1 / Claude | 0 | 10 | 70 |
| Mode 2 / Cursor | 1 | 80 | 70 |
| Mode 3 / Codex | 2 | 150 | 70 |
| Mode 4 / N/A | 3 | 220 | 70 |

Mac 上位机需要使用固定分区，不能再按单模式 74 帧写入，否则有覆盖其他模式动图/图片的风险。

OLED 相关协议仍是：

```text
AA BB 80 [flag] [chunk_len:2 LE] [address:4 LE] CC DD
AA BB 82 [mode] [start_index:2 LE] [frame_count:2 LE] [time_delay:2 LE] CC DD
AA BB 83 [mode] CC DD
```

上传保护建议：

- 源文件上限：2 MB
- FPS 范围：1..30
- 单模式帧数上限：70
- 超过限制时，上位机直接弹窗拒绝，不进入上传
- 上传时暂停状态轮询，避免命令通道被查询状态抢占
- 上传失败后 UI 必须退出“上传中/同步中”，允许用户重新连接和重试
- 成功写完所有帧后必须发送 `0x82` 更新图片元数据

## 3. Windows 上位机已经完成的能力

Windows 侧已经围绕最新固件做过一轮同步，Mac 可参考这些功能目标，不一定照搬实现方式。

已完成项：

1. 支持 4 个模式。
2. UI 左侧模式名使用 Claude、Cursor、Codex、N/A。
3. 支持每个模式、每个 AI 状态配置不同灯效。
4. 支持灯条亮度设置与测试。
5. 支持灯效直接预览。
6. 支持上位机切换模式时通过 `0x92` 同步切换键盘。
7. 支持 OLED GIF/图片上传保护：
   - 2 MB 源文件限制
   - 每模式 70 帧限制
   - FPS 1..30
   - 上传时暂停状态查询
   - 上传失败不让软件永久卡在“同步中”
8. 支持 USB 有线配置通道，并且 USB 优先级高于 BLE。
9. 修复 BLE 和 USB 同时存在时保存配置卡住的问题。
10. 去掉不稳定的实体按键/UI 联动动画、灯条实时渲染、GIF 实时同步预览等非核心功能，优先保证连接、保存、上传稳定。

## 4. macOS 当前代码与最新固件的差异

以下是我在 macOS 目录里看到的现状。

### 4.1 模式数量仍是 3 个

文件：

`Sources/Models/AhaKeyStudioModels.swift`

当前只有：

```swift
case mode0 = 0
case mode1 = 1
case mode2 = 2
```

需要新增：

```swift
case mode3 = 3
```

并同步修改：

- `title`
- `shortTitle`
- `name`
- `subtitle`
- `guidance`
- 所有 `AhaKeyModeSlot.allCases` 相关逻辑
- 默认按键配置
- 默认灯效配置
- 默认 OLED 配置
- 本地持久化数据迁移

建议用户显示：

- Claude
- Cursor
- Codex
- N/A

协议值仍然是 `0..3`。

### 4.2 协议层缺少新命令

文件：

`Sources/BLE/AhaKeyProtocol.swift`

当前能看到：

- `0x73` 自定义按键
- `0x80` 准备写 Flash
- `0x81` 写结果
- `0x82` 更新 OLED 图片元数据
- `0x83` 读取图片状态
- `0x90` AI 状态更新

当前没有看到：

- `0x84` 每模式 AI 状态灯效表
- `0x85` 灯条亮度
- `0x91` 灯效预览
- `0x92` 上位机切换键盘模式

建议在 `AhaKeyCommand` 增加：

```swift
static let cmdSetAILightConfig: UInt8 = 0x84
static let cmdSetLightBrightness: UInt8 = 0x85
static let cmdPreviewLightEffect: UInt8 = 0x91
static let cmdSetWorkMode: UInt8 = 0x92

static func setAILightConfig(mode: UInt8, effects: [UInt8]) -> Data {
    Data(header + [cmdSetAILightConfig, mode] + Array(effects.prefix(9)) + trailer)
}

static func setLightBrightness(_ value: UInt8) -> Data {
    Data(header + [cmdSetLightBrightness, value] + trailer)
}

static func previewLightEffect(_ effect: UInt8) -> Data {
    Data(header + [cmdPreviewLightEffect, effect] + trailer)
}

static func setWorkMode(_ mode: UInt8) -> Data {
    Data(header + [cmdSetWorkMode, mode] + trailer)
}
```

同时在 `AhaKeyBLEManager` 里加对应 async 发送方法，建议都走已有命令队列和超时机制。

### 4.3 OLED 帧数上限当前不对

文件：

`Sources/BLE/AhaKeyProtocol.swift`

当前：

```swift
static let oledMaxFrames = 74
```

需要改成按最新固件保护逻辑：

```swift
static let oledFactoryReservedSlots = 10
static let oledModeCount = 4
static let oledMaxFramesPerMode = 70
```

或者通过 `0x83` 返回的 `allModeMaxPic` 动态确认，但 UI 侧仍建议硬限制 70，避免覆盖其他模式。

上传起始 slot：

```swift
let startIndex = 10 + mode.rawValue * 70
```

### 4.4 默认 OLED 资源不完整

文件：

`Sources/Utilities/DefaultOLEDAssets.swift`

当前资源目录只有：

- `Resources/DefaultOLED/claude_0.gif`
- `Resources/DefaultOLED/cursor_0.gif`

当前逻辑：

- Mode 0 使用 `claude_0`
- Mode 1 使用 `cursor_0`
- Mode 2 返回 nil

最新固件侧 Mode 1、Mode 2、Mode 3 都已有对应出厂显示内容。Mac 上位机如果想和固件/Windows 同步，建议补齐：

- Claude 默认 GIF
- Cursor 默认 GIF/图片
- Codex 默认 GIF/图片
- Mode 4 / N/A 可为空或使用占位

如果 Mac App 内置默认素材，构建脚本必须把 `Resources/DefaultOLED` 复制到：

```text
AhaKey Studio.app/Contents/Resources/DefaultOLED/
```

### 4.5 状态查询解析可能未包含亮度

文件：

`Sources/BLE/AhaKeyProtocol.swift`

当前 `AhaKeyDeviceStatus` 字段是：

- battery
- signal
- firmwareMain
- firmwareSub
- workMode
- lightMode
- switchState

固件设备状态里现在额外带了亮度字段，Windows 侧会读取并用于 UI。Mac 侧需要确认固件返回长度，如果有第 8 个状态字节，解析为：

```swift
let brightness = Int(payload[base + 7])
```

兼容策略：

- 旧固件没有这个字节时，亮度显示默认 35。
- 新固件有这个字节时，使用设备实际值。

### 4.6 macOS 不需要 BLE_TCP_driver.exe

Windows 侧有 `BLE_tcp_driver.exe`，这是 Windows BLE 桥接程序。

macOS 侧不需要这个 exe。Mac 代码目前使用：

- CoreBluetooth 直接连接键盘 BLE
- `ahakeyconfig-agent` 常驻/Hook 辅助进程
- Agent 与主 App 之间有连接所有权/诊断逻辑

Mac 同事需要注意：Mac 上不是补一个 Windows BLE TCP Driver，而是继续使用 CoreBluetooth + Agent 的方式。需要确保主 App 和 Agent 不同时抢占同一个 BLE 连接，状态灯 Hook 下发时必须由当前 BLE 持有者发送 `0x90`。

### 4.7 USB 有线配置通道目前 Mac 侧未看到实现

Windows 侧已经做了 USB HID 配置通道，USB 优先级高于 BLE。

macOS 目录里目前只看到 CoreBluetooth 路径，没有看到 IOKit/IOHIDManager 的 USB HID 配置传输实现。

如果 Mac 要同步有线配置，需要新增一个 macOS USB HID Transport。建议思路：

1. 使用 `IOHIDManager` 枚举 AhaKey USB HID 设备。
2. 通过 VID/PID、产品名或报告描述符筛选设备。
3. 和 BLE 使用同一套业务协议帧：

```text
AA BB [cmd] [payload] CC DD
```

4. 外层用 USB HID 报告承载，和 Windows 保持一致：

```text
report[0] = 0x00   // Report ID，如设备要求
report[1] = 0xA1   // command packet
report[2] = len
report[3...] = AA BB ... CC DD
```

大块 OLED 数据包使用：

```text
report[1] = 0xA2   // data packet
report[2] = len
report[3...] = data chunk
```

5. 传输选择建议：
   - 如果 USB HID 已连接并可写，优先 USB。
   - 否则使用 BLE。
   - 同一时间不要让 BLE 和 USB 同时执行保存/上传。

如果本阶段 Mac 不做 USB，则 UI 必须明确标注“有线配置暂未支持”，避免用户以为插线后可以配置。

## 5. Mac 代码建议改动清单

### 5.1 协议层

修改文件：

`Sources/BLE/AhaKeyProtocol.swift`

需要：

1. 加 `0x84/0x85/0x91/0x92` 常量和构包方法。
2. 把 OLED 最大帧数从 74 改成每模式 70。
3. 增加 Mode 4 分区计算。
4. 状态查询解析兼容亮度字段。
5. UI 展示 FPS 上限改成 30。

### 5.2 BLE 管理层

修改文件：

`Sources/BLE/AhaKeyBLEManager.swift`

需要：

1. 增加：
   - `setAILightConfig(mode:effects:)`
   - `setLightBrightness(_:)`
   - `previewLightEffect(_:)`
   - `setWorkMode(_:)`
2. 所有命令通过现有队列串行发送。
3. 上传 OLED 时继续暂停状态轮询。
4. 收到任意有效响应时更新连接心跳，避免上传中误判 BLE 超时。
5. 上传失败时清理 `oledUploadProgress` 和 UI 同步状态。

### 5.3 模式与默认配置

修改文件：

`Sources/Models/AhaKeyStudioModels.swift`

需要：

1. 新增 `mode3 = 3`。
2. UI 显示改成 Claude、Cursor、Codex、N/A。
3. 用户可见 Mode 编号从 1 开始。
4. 第 4 个键默认文案与默认 HID 改成 Backspace。
5. 默认灯效表覆盖 4 个模式 x 9 个 AI 状态。
6. 本地配置读写要支持旧版 3 模式数据迁移到 4 模式。

### 5.4 UI

主要文件：

`Sources/Views/AhaKeyStudioView.swift`

需要：

1. 模式切换时调用 `0x92`。
2. 增加 AI 状态灯效设置区：
   - 4 个模式都能配置
   - 每个模式 9 个状态
   - 状态顺序按会话流程排列
   - 每行可选灯效
   - 每行有测试按钮，调用 `0x91`
3. 增加亮度设置：
   - Slider/Input 范围 `1..100`
   - 默认 35
   - 测试按钮调用 `0x85`
4. OLED 上传文案改成“选择 GIF 或图片”。
5. 上传前做硬限制校验：
   - 源文件 > 2 MB：拒绝
   - 帧数 > 70：拒绝
   - FPS 超过 30：拒绝
6. 去掉或避免过度承诺的实时预览文案。不要展示“会实时和键盘完全一致”这类当前不稳定的描述。

### 5.5 默认 OLED 资源

修改文件/目录：

- `Sources/Utilities/DefaultOLEDAssets.swift`
- `Resources/DefaultOLED`

需要：

1. 补齐 Mode 2 / Cursor、Mode 3 / Codex 对应默认素材。
2. Mode 4 可保留 nil 或提供 N/A 占位。
3. 构建脚本必须复制资源到 App bundle。

### 5.6 Hook/Agent

相关文件：

- `Sources/Agent/HookClient.swift`
- `Sources/Utilities/AgentManager.swift`
- `Sources/Utilities/VoiceRelayService.swift`
- `Sources/Views/DeviceInfoView.swift`

当前 Mac 已经有 Claude/Cursor/Codex Hook 逻辑，也能发 `0x90` 状态。需要确认：

1. Hook 只发送当前 AI 状态，不再自己直接决定具体灯效。
2. `0x90` 发送时，BLE 连接所有权在 Agent 或主 App 手里必须明确。
3. Mode 4 加入后，所有 `AhaKeyModeSlot.allCases` 循环不会漏掉新模式。
4. VoiceRelayService 里按模式绑定语音键/F18 的逻辑要确认 Mode 4 的默认行为，不能因为新增模式导致数组越界或配置丢失。

## 6. DMG 构建建议

当前 `Makefile` 依赖缺失的 `scripts/build.sh`，建议 Mac 同事补一个打包脚本。

脚本需要完成：

1. `swift build -c release --product AhaKeyConfig`
2. `swift build -c release --product ahakeyconfig-agent`
3. 创建：

```text
AhaKey Studio.app/
  Contents/
    MacOS/
      AhaKeyConfig
    Resources/
      ahakeyconfig-agent
      DefaultOLED/
      AppIcon.icns
    Info.plist
```

4. 复制 `Resources/DefaultOLED`。
5. 根据 `Packaging/AhaKeyConfig-EmbeddedInfo.plist` 或独立 Info.plist 生成 App 信息。
6. 如需发布：
   - `codesign`
   - `notarytool`
   - `stapler`
7. 用 `hdiutil create` 或 `create-dmg` 生成 DMG。

## 7. Mac 同步后的测试大纲

### 7.1 基础连接

1. 打开 Mac App。
2. 通过 BLE 连接键盘。
3. 设备状态能显示：
   - 电量
   - 固件版本
   - 当前模式
   - 当前灯效
   - 拨杆状态
   - 亮度
4. 如果 Mac 未实现 USB，插 USB 时 UI 不应误提示“有线配置可用”。

### 7.2 模式同步

1. App 上切换 Claude，键盘同步到 Mode 1。
2. App 上切换 Cursor，键盘同步到 Mode 2。
3. App 上切换 Codex，键盘同步到 Mode 3。
4. App 上切换 N/A，键盘同步到 Mode 4。
5. 每次切换后，键盘先显示四个按键名称，随后恢复对应 OLED 动图/图片。

### 7.3 快捷键配置

1. 分别修改 4 个模式里的 4 个按键。
2. 保存配置。
3. 断开重连后重新读取。
4. 确认第 4 个键默认是 Backspace，不是 Enter。

### 7.4 AI 状态灯效

1. 每个模式都配置 9 个 AI 状态灯效。
2. 保存后断开重连，确认配置仍在。
3. 用测试按钮调用 `0x91`，键盘能立即显示对应灯效。
4. 用 Hook 触发 `0x90`：
   - Claude SessionStart
   - UserPromptSubmit
   - PreToolUse
   - PermissionRequest
   - PostToolUse
   - Stop
5. 确认键盘显示的是“当前模式 + 当前状态”对应的灯效。

### 7.5 亮度

1. 默认亮度读取为 35。
2. 设置 20，灯条变暗。
3. 设置 35，恢复默认亮度。
4. 设置 100，灯条明显变亮。
5. 输入 0、101 或非法值时，UI 应拒绝或修正到合法范围。

### 7.6 OLED 上传

1. 上传 1 张图片，成功。
2. 上传 8 帧 GIF，成功。
3. 上传接近 70 帧 GIF，成功。
4. 上传超过 70 帧，UI 直接弹窗拒绝，不开始上传。
5. 上传超过 2 MB 源文件，UI 直接弹窗拒绝。
6. FPS 设置 30，成功。
7. FPS 设置超过 30，UI 直接限制或拒绝。
8. 上传中断开 BLE，UI 退出上传状态，允许重新连接和重试。
9. 上传失败后，短按键盘切换模式，屏幕应能从按键名称页恢复到对应 OLED 图片/GIF。

### 7.7 Hook/Agent

1. 安装 Claude Hooks。
2. 安装 Cursor Hooks。
3. 安装 Codex Hooks。
4. Agent 持有 BLE 时，Hook 状态能下发到键盘。
5. 主 App 打开时，不应和 Agent 互相抢 BLE 导致状态灯失效。
6. 拨杆自动/手动批准状态能被 Hook 正确读取。

### 7.8 USB 有线配置

如果 Mac 实现 USB HID Transport，需要测试：

1. 只插 USB，不连接 BLE，能读取设备状态。
2. 只插 USB，能保存快捷键。
3. 只插 USB，能设置亮度。
4. 只插 USB，能预览灯效。
5. 只插 USB，能上传 OLED 图片/GIF。
6. USB 和 BLE 同时存在时，上位机优先使用 USB，且不会卡在“同步中”。
7. 拔掉 USB 后，能自动回退 BLE 或提示用户重新连接。

如果 Mac 暂不实现 USB，则这部分应明确标注为未支持，不要让用户进入 USB 配置流程。

## 8. 优先级建议

建议 Mac 同事按以下顺序同步：

1. 修复/补齐构建脚本，先保证 macOS 能打出 App/DMG。
2. 协议层补 `0x84/0x85/0x91/0x92`。
3. 模式从 3 个扩展到 4 个。
4. OLED 上传限制改成每模式 70 帧、FPS 1..30。
5. 增加亮度 UI 与灯效预览。
6. 增加每模式 9 状态灯效配置 UI。
7. 验证 Hook 只发 `0x90` 状态，具体灯效由固件决定。
8. 评估是否做 macOS USB HID Transport。如果时间紧，先保 BLE 稳定。

## 9. 给 Mac 同事的关键提醒

1. 不要把 Windows 的 `BLE_tcp_driver.exe` 搬到 Mac。Mac 走 CoreBluetooth + Agent。
2. 协议帧本身和 Windows 一致，都是 `AA BB ... CC DD`。
3. USB 如果要做，只是外层传输不同，里面仍然发同一套固件协议。
4. OLED 上传不要再按 74 帧设计。当前 4 模式下每模式安全上限是 70 帧。
5. App 切换模式必须发 `0x92`，不能只切 UI。
6. Hook 只发 `0x90` 状态，不要在 Hook 里重复设计灯效映射。
7. 亮度协议是 `0x85`，默认值是 35。
8. 灯效表协议是 `0x84`，每个模式 9 个状态都要覆盖。
9. 预览灯效协议是 `0x91`。
10. 第 4 个键默认是 Backspace。

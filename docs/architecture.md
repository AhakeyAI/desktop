# Architecture

## 组织原则

- `desktop` 是 AhaKey-X1 的多平台 monorepo,按**客户端 / 组件**组织源码,而不是把不同技术栈混在同一目录。
- 各桌面客户端(macOS / Windows / Linux)保留各自的运行时、UI 结构、系统集成方式与构建链路。
- 设备侧的共享组件(键盘固件、BLE ↔ TCP 桥接)独立成顶层目录。

## 客户端与组件

### macOS — `ahakeyconfig-mac/`(主力)

- Swift / SwiftUI 原生客户端,由仓库根 `Package.swift` 构建(target `AhaKeyConfig`)。
- `Sources/Agent/` — 后台守护进程 `ahakeyconfig-agent`:维持 BLE 连接,并按键盘物理拨杆状态回应各 IDE 的审批 hook(`ClaudeHookHandler` / `CursorHookHandler` / `CodexHookHandler` / `KimiHookHandler`,共享 `HookSupport`)。
- `Sources/` — 设备配置、BLE 通信、OLED 资源、voice agent、工作台 UI。
- `Resources/` — 运行所需资源。
- `scripts/` — 构建、签名、DMG 打包脚本。

### Windows

- `ahakeyconfig-win-java/` — Java · JavaFX(Maven),入口 `com.example.ahakey.Main`。
- `ahakeyconfig-win-python/` — Python · PyInstaller(Capswriter 基线),入口 `main.py`;`hook/` 下含 IDE hook 安装。

### Linux — `ahakeyconfig-ubuntu-java/`

- Java · JavaFX(Maven),入口 `com.example.ahakey.Main`;含 Linux 语音输入(`LinuxVoiceConfig`)等。

### 共享设备组件

- `CH582m_vibe_coding_BLE_keyboard-master/` — 键盘固件(C,CH582M MCU)。
- `BLE_tcp_bridge/` — BLE ↔ TCP 桥接(C#),供非原生客户端通过本地 TCP 与设备交互。

## 拨杆审批闸门

各平台客户端都把键盘的物理**拨杆**当作 AI coding agent 的硬件审批闸门:拨到「自动」时 Claude / Cursor / Codex / Kimi 的工具调用自动放行,拨回时交回人工确认。守护进程通过 BLE 读拨杆状态并回应每个 IDE hook —— **fail-safe:读不到拨杆时一律默认「交人确认」,绝不误放行。**

## 当前边界

- 云端后端不在本仓库。
- 各客户端不共享目录结构。
- 构建产物不应入库,发布走 GitHub Releases。

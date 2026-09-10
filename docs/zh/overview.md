# AhaKey Desktop 项目概览

[English](../overview.md) · [简体中文](overview.md) · [项目首页](README.md)

`AhakeyAI/desktop` 是 **AhaKey-X1（Vibecoding Keyboard）** 桌面套件的官方源码 monorepo —— 把这把物理键盘变成「AI 辅助编程控制台」的配套软件与工具链。

## 它能做什么

1. **键盘控制** —— 通过 BLE 连接 AhaKey-X1,配置 4 键 × 3 模式键位映射、推送 OLED 图片、把 IDE 状态映射到 LED 灯条。
2. **拨杆审批 AI** —— 键盘上的物理**拨杆**是 AI coding agent 的硬件闸门。拨到「自动」,Claude Code / Cursor / Codex / Kimi 的工具调用自动放行;拨回来,每个动作都交回人工确认。后台 agent 通过 BLE 读拨杆状态,据此回应各 IDE 的 hook —— **设计上 fail-safe:读不到拨杆时一律默认「交人确认」,绝不误放行。**
3. **本机语音 Agent**（macOS）—— 一个本地、语音优先的助手,走 OpenAI 协议调用 LLM,并以用户自己的身份操作生产力工具(飞书 / Lark 等)。

## 客户端与组件

| 组件 | 目录 | 技术栈 | 说明 |
|---|---|---|---|
| **macOS 应用** | `ahakeyconfig-mac/` | Swift · SwiftUI · CoreBluetooth | 主力开发;由根 `Package.swift` 构建 |
| **Windows 应用** | `ahakeyconfig-win-java/` | Java · JavaFX（Maven） | Windows 桌面客户端 |
| **Windows 应用（旧版）** | `ahakeyconfig-win-python/` | Python · PyInstaller | 迁入基线（源自 Capswriter） |
| **Linux 应用** | `ahakeyconfig-ubuntu-java/` | Java · JavaFX（Maven） | Ubuntu 桌面客户端 |
| **BLE ↔ TCP 桥接** | `BLE_tcp_bridge/` | C# | 把 BLE 桥接到本地 TCP,供非原生客户端使用 |

macOS 客户端是主力实现:原生 SwiftUI + CoreBluetooth 链路(中间没有 Python / .NET / TCP 桥接),交付一个签名 `.app` 加一个后台 `ahakeyconfig-agent` LaunchAgent —— GUI 关掉后仍持续回应 IDE hook、推送 LED 状态。

## macOS 主要能力

- **原生 BLE 栈** —— 单个签名 `.app` + 常驻 `ahakeyconfig-agent`。
- **AI hook** —— 各 IDE 独立 handler（`ClaudeHookHandler` / `CursorHookHandler` / `CodexHookHandler` / `KimiHookHandler`）共用 `HookSupport` 核心,驱动拨杆审批流程。
- **Voice Agent** —— `VoiceAgent` 模块,supervisor + sub-agent 编排,结构化工具调用、独立记忆,配 OpenAI 协议兼容的 `LLMClient`;会话跨次启动保留。
- **飞书 / Lark** —— 通过 `lark-cli` 以用户自己的身份发消息、查联系人,App 不保存飞书凭证。
- **语音输入 HUD** —— 基于 Apple Speech 的浮动「按住说话」浮层,为 IDE / 微信等做了中继路由。

## 插件 SDK

使用 `@ahakey/plugin-sdk` 开发 TypeScript 插件，或集成 Swift `AhaKeyPluginKit` 宿主库。请从 [SDK 总览](sdk.md)和 [TypeScript 指南](typescript-sdk.md)开始，了解完整插件开发流程、宿主 API、权限、生命周期及可运行的 macOS 示例。

## 构建（macOS）

```bash
# 在仓库根目录 —— 根 Package.swift 驱动 macOS targets
swift build                       # 编译全部 target
swift build -c release            # release 构建
```

产出 `AhaKeyConfig` 应用可执行文件与 `ahakeyconfig-agent` 辅助进程。打包成 `.app` 以及其他平台的构建步骤见 [`docs/installation.md`](../installation.md)。

## 仓库结构

```
desktop/
├── ahakeyconfig-mac/         # macOS 客户端 — Swift + SwiftUI（活跃）
├── ahakeyconfig-win-java/    # Windows 客户端 — Java
├── ahakeyconfig-win-python/  # Windows 客户端 — Python / PySide6（旧版基线）
├── ahakeyconfig-ubuntu-java/ # Linux 客户端 — Java
├── BLE_tcp_bridge/           # BLE ↔ TCP 桥接 — C#
├── Package.swift             # macOS targets 的根 SwiftPM 清单
├── sdks/                     # 插件 SDK、指南与示例
├── docs/                     # 仓库级文档（架构、BLE 协议、发布）
└── assets/                   # 共享品牌 / 构建资源
```

## 仓库范围

只保留源码、工程文件、必要资源与文档。**构建产物不应入库** —— 不应提交 `.app` / `.dmg` / `.exe` / `.class` / `.o`（以及 `*/target/` 等构建目录），安装包统一走 [GitHub Releases](https://github.com/AhakeyAI/desktop/releases)。

## 新同学先读

- [`docs/repo-layout.md`](../repo-layout.md) · [`docs/architecture.md`](../architecture.md) · [`docs/ble-protocol.md`](../ble-protocol.md)
- [`docs/installation.md`](../installation.md) · [`docs/releases.md`](../releases.md) · [`docs/supported-platforms.md`](../supported-platforms.md)

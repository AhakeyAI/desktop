<div align="center">

# ⌨️ AhaKey Desktop

**The official cross-platform desktop suite for the AhaKey-X1 — the Vibecoding Keyboard.**

**AhaKey-X1（Vibecoding Keyboard）官方跨平台桌面端 · 键盘控制 + 拨杆审批 + 本机语音 Agent**

[**English**](#-english) &nbsp;·&nbsp; [**简体中文**](#-简体中文)

<br/>

<!-- Release & CI -->
<a href="https://github.com/AhakeyAI/desktop/releases"><img src="https://img.shields.io/github/v/release/AhakeyAI/desktop?include_prereleases&label=release&color=4F46E5" alt="Latest Release"></a>
<a href="https://github.com/AhakeyAI/desktop/actions"><img src="https://img.shields.io/github/actions/workflow/status/AhakeyAI/desktop/release.yml?label=build" alt="Build"></a>
<a href="https://github.com/AhakeyAI/desktop/commits/main"><img src="https://img.shields.io/github/last-commit/AhakeyAI/desktop?color=informational" alt="Last Commit"></a>
<a href="https://github.com/AhakeyAI/desktop/stargazers"><img src="https://img.shields.io/github/stars/AhakeyAI/desktop?style=flat&color=yellow" alt="Stars"></a>

<br/>

<!-- Platforms & Tech -->
<img src="https://img.shields.io/badge/macOS-12%2B-000000?logo=apple&logoColor=white" alt="macOS 12+">
<img src="https://img.shields.io/badge/Windows-10%2F11-0078D6?logo=windows&logoColor=white" alt="Windows 10/11">
<img src="https://img.shields.io/badge/Linux-Ubuntu-E95420?logo=ubuntu&logoColor=white" alt="Ubuntu">
<img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
<img src="https://img.shields.io/badge/Java-17%2B-007396?logo=openjdk&logoColor=white" alt="Java 17+">
<img src="https://img.shields.io/badge/Python-3.10%2B-3776AB?logo=python&logoColor=white" alt="Python 3.10+">

</div>

---

<a id="-english"></a>

## 🇬🇧 English

`AhakeyAI/desktop` is the official source monorepo for the **AhaKey-X1 (Vibecoding Keyboard)** desktop suite — the companion software, keyboard firmware, and tooling that turn the physical keyboard into a control surface for AI-assisted coding.

### What it does

1. **Keyboard control** — connect to the AhaKey-X1 over BLE, configure the 4-key × 3-mode mapping, push OLED art, and mirror your IDE's state onto the LED light bar.
2. **Lever-gated AI approval** — the keyboard's physical **lever** is a hardware gate for your AI coding agent. Flip it to *auto* and tool calls from Claude Code / Cursor / Codex / Kimi are auto-approved; flip it back and every action is handed back for manual confirmation. A background agent reads the lever over BLE and answers each IDE hook accordingly — **fail-safe by design: if the lever can't be read, it defaults to *ask*, never *allow*.**
3. **On-device voice agent** *(macOS)* — a local, voice-first assistant that talks to LLMs over the OpenAI protocol and reaches into productivity tools (e.g. Feishu / Lark) under your own identity.

### Clients & components

| Component | Directory | Stack | Notes |
|---|---|---|---|
| **macOS app** | `ahakeyconfig-mac/` | Swift · SwiftUI · CoreBluetooth | Actively developed; built from the root `Package.swift` |
| **Windows app** | `ahakeyconfig-win-java/` | Java · JavaFX (Maven) | Windows desktop client |
| **Windows app (legacy)** | `ahakeyconfig-win-python/` | Python · PyInstaller | Imported baseline (Capswriter-derived) |
| **Linux app** | `ahakeyconfig-ubuntu-java/` | Java · JavaFX (Maven) | Ubuntu desktop client |
| **Keyboard firmware** | `CH582m_vibe_coding_BLE_keyboard-master/` | C (CH582M MCU) | BLE keyboard firmware source |
| **BLE ↔ TCP bridge** | `BLE_tcp_bridge/` | C# | Bridges BLE to a local TCP socket for non-native clients |

The macOS client is the lead implementation: a native SwiftUI + CoreBluetooth stack (no Python / .NET / TCP bridge in the loop), shipping a signed `.app` plus a background `ahakeyconfig-agent` LaunchAgent that keeps answering IDE hooks and pushing LED state after the GUI closes.

### macOS highlights

- **Native BLE stack** — one signed `.app` bundle + a long-lived `ahakeyconfig-agent`.
- **AI hooks** — per-IDE handlers (`ClaudeHookHandler`, `CursorHookHandler`, `CodexHookHandler`, `KimiHookHandler`) on a shared `HookSupport` core, driving the lever-gated approval flow.
- **Voice Agent** — a `VoiceAgent` module with a supervisor + sub-agent orchestrator, structured tool-calling, per-agent memory, and an OpenAI-compatible `LLMClient`; sessions persist across launches.
- **Feishu / Lark** — send messages and resolve contacts via `lark-cli` under your own identity; the app never stores Feishu credentials.
- **Voice input HUD** — a floating push-to-talk overlay backed by Apple Speech, with relay routes for IDEs, WeChat, etc.

### Build (macOS)

```bash
# from the repo root — the root Package.swift drives the macOS targets
swift build                       # compile all targets
swift build -c release            # release build
```

This produces the `AhaKeyConfig` app executable and the `ahakeyconfig-agent` helper. See [`docs/installation.md`](docs/installation.md) for packaging into a `.app` and the other platforms' build steps.

### Repository layout

```
desktop/
├── ahakeyconfig-mac/         # macOS client — Swift + SwiftUI (active)
├── ahakeyconfig-win-java/    # Windows client — Java
├── ahakeyconfig-win-python/  # Windows client — Python / PySide6 (legacy baseline)
├── ahakeyconfig-ubuntu-java/ # Linux client — Java
├── CH582m_vibe_coding_BLE_keyboard-master/  # Keyboard firmware — C (CH582M)
├── BLE_tcp_bridge/           # BLE ↔ TCP bridge — C#
├── Package.swift             # Root SwiftPM manifest for the macOS targets
├── docs/                     # Repo-level docs (architecture, BLE protocol, releases)
└── assets/                   # Shared brand / build assets
```

### Repository scope

Source, project files, required assets, and docs only. **Build artifacts are not committed** — no `.app` / `.dmg` / `.exe` / `.class` / `.o`. Installers are distributed exclusively through [GitHub Releases](https://github.com/AhakeyAI/desktop/releases).

### Start here

- [`docs/repo-layout.md`](docs/repo-layout.md) · [`docs/architecture.md`](docs/architecture.md) · [`docs/ble-protocol.md`](docs/ble-protocol.md)
- [`docs/installation.md`](docs/installation.md) · [`docs/releases.md`](docs/releases.md) · [`docs/supported-platforms.md`](docs/supported-platforms.md)

---

<a id="-简体中文"></a>

## 🇨🇳 简体中文

`AhakeyAI/desktop` 是 **AhaKey-X1（Vibecoding Keyboard）** 桌面套件的官方源码 monorepo —— 把这把物理键盘变成「AI 辅助编程控制台」的配套软件、键盘固件与工具链。

### 它能做什么

1. **键盘控制** —— 通过 BLE 连接 AhaKey-X1,配置 4 键 × 3 模式键位映射、推送 OLED 图片、把 IDE 状态映射到 LED 灯条。
2. **拨杆审批 AI** —— 键盘上的物理**拨杆**是 AI coding agent 的硬件闸门。拨到「自动」,Claude Code / Cursor / Codex / Kimi 的工具调用自动放行;拨回来,每个动作都交回人工确认。后台 agent 通过 BLE 读拨杆状态,据此回应各 IDE 的 hook —— **设计上 fail-safe:读不到拨杆时一律默认「交人确认」,绝不误放行。**
3. **本机语音 Agent**（macOS）—— 一个本地、语音优先的助手,走 OpenAI 协议调用 LLM,并以用户自己的身份操作生产力工具(飞书 / Lark 等)。

### 客户端与组件

| 组件 | 目录 | 技术栈 | 说明 |
|---|---|---|---|
| **macOS 应用** | `ahakeyconfig-mac/` | Swift · SwiftUI · CoreBluetooth | 主力开发;由根 `Package.swift` 构建 |
| **Windows 应用** | `ahakeyconfig-win-java/` | Java · JavaFX（Maven） | Windows 桌面客户端 |
| **Windows 应用（旧版）** | `ahakeyconfig-win-python/` | Python · PyInstaller | 迁入基线（源自 Capswriter） |
| **Linux 应用** | `ahakeyconfig-ubuntu-java/` | Java · JavaFX（Maven） | Ubuntu 桌面客户端 |
| **键盘固件** | `CH582m_vibe_coding_BLE_keyboard-master/` | C（CH582M 单片机） | BLE 键盘固件源码 |
| **BLE ↔ TCP 桥接** | `BLE_tcp_bridge/` | C# | 把 BLE 桥接到本地 TCP,供非原生客户端使用 |

macOS 客户端是主力实现:原生 SwiftUI + CoreBluetooth 链路(中间没有 Python / .NET / TCP 桥接),交付一个签名 `.app` 加一个后台 `ahakeyconfig-agent` LaunchAgent —— GUI 关掉后仍持续回应 IDE hook、推送 LED 状态。

### macOS 主要能力

- **原生 BLE 栈** —— 单个签名 `.app` + 常驻 `ahakeyconfig-agent`。
- **AI hook** —— 各 IDE 独立 handler（`ClaudeHookHandler` / `CursorHookHandler` / `CodexHookHandler` / `KimiHookHandler`）共用 `HookSupport` 核心,驱动拨杆审批流程。
- **Voice Agent** —— `VoiceAgent` 模块,supervisor + sub-agent 编排,结构化工具调用、独立记忆,配 OpenAI 协议兼容的 `LLMClient`;会话跨次启动保留。
- **飞书 / Lark** —— 通过 `lark-cli` 以用户自己的身份发消息、查联系人,App 不保存飞书凭证。
- **语音输入 HUD** —— 基于 Apple Speech 的浮动「按住说话」浮层,为 IDE / 微信等做了中继路由。

### 构建（macOS）

```bash
# 在仓库根目录 —— 根 Package.swift 驱动 macOS targets
swift build                       # 编译全部 target
swift build -c release            # release 构建
```

产出 `AhaKeyConfig` 应用可执行文件与 `ahakeyconfig-agent` 辅助进程。打包成 `.app` 以及其他平台的构建步骤见 [`docs/installation.md`](docs/installation.md)。

### 仓库结构

```
desktop/
├── ahakeyconfig-mac/         # macOS 客户端 — Swift + SwiftUI（活跃）
├── ahakeyconfig-win-java/    # Windows 客户端 — Java
├── ahakeyconfig-win-python/  # Windows 客户端 — Python / PySide6（旧版基线）
├── ahakeyconfig-ubuntu-java/ # Linux 客户端 — Java
├── CH582m_..._keyboard-master/  # 键盘固件 — C（CH582M）
├── BLE_tcp_bridge/           # BLE ↔ TCP 桥接 — C#
├── Package.swift             # macOS targets 的根 SwiftPM 清单
├── docs/                     # 仓库级文档（架构、BLE 协议、发布）
└── assets/                   # 共享品牌 / 构建资源
```

### 仓库范围

只保留源码、工程文件、必要资源与文档。**构建产物不应入库** —— 不应提交 `.app` / `.dmg` / `.exe` / `.class` / `.o`（以及 `*/target/` 等构建目录），安装包统一走 [GitHub Releases](https://github.com/AhakeyAI/desktop/releases)。

### 新同学先读

- [`docs/repo-layout.md`](docs/repo-layout.md) · [`docs/architecture.md`](docs/architecture.md) · [`docs/ble-protocol.md`](docs/ble-protocol.md)
- [`docs/installation.md`](docs/installation.md) · [`docs/releases.md`](docs/releases.md) · [`docs/supported-platforms.md`](docs/supported-platforms.md)

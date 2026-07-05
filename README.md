<a id="top"></a>

<p align="center">
  <a href="#zh-cn"><strong>简体中文</strong></a> ·
  <a href="#en"><strong>English</strong></a>
</p>

---

<a id="zh-cn"></a>

<h1 align="center">⌨️ AhaKey Desktop</h1>

<p align="center">
  <strong>AhaKey X1 官方跨平台桌面客户端</strong>
</p>

<p align="center">
  设备连接 · 键位配置 · 拨杆审批 · AI 状态同步 · 本机语音 Agent
</p>

<p align="center">
  <a href="https://github.com/AhakeyAI/desktop/releases"><img src="https://img.shields.io/github/v/release/AhakeyAI/desktop?include_prereleases&label=release&color=4F46E5" alt="Latest Release"></a>
  <a href="https://github.com/AhakeyAI/desktop/actions"><img src="https://img.shields.io/github/actions/workflow/status/AhakeyAI/desktop/release.yml?label=build" alt="Build"></a>
  <a href="https://github.com/AhakeyAI/desktop/commits/main"><img src="https://img.shields.io/github/last-commit/AhakeyAI/desktop?color=informational" alt="Last Commit"></a>
  <a href="https://github.com/AhakeyAI/desktop/stargazers"><img src="https://img.shields.io/github/stars/AhakeyAI/desktop?style=flat&color=yellow" alt="Stars"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-12%2B-000000?logo=apple&logoColor=white" alt="macOS 12+">
  <img src="https://img.shields.io/badge/Windows-10%2F11-0078D6?logo=windows&logoColor=white" alt="Windows 10/11">
  <img src="https://img.shields.io/badge/Linux-Ubuntu-E95420?logo=ubuntu&logoColor=white" alt="Ubuntu">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/Java-17%2B-007396?logo=openjdk&logoColor=white" alt="Java 17+">
  <img src="https://img.shields.io/badge/Python-3.10%2B-3776AB?logo=python&logoColor=white" alt="Python 3.10+">
</p>

---

## AhaKey Desktop 是什么？

`AhakeyAI/desktop` 是 **AhaKey X1（Vibecoding Keyboard）官方桌面客户端仓库**。

它负责把 AhaKey X1 这把物理键盘连接到你的电脑和 AI 编程工作流中，包括：

* 连接 AhaKey X1 设备
* 配置按键和基础交互
* 读取拨杆状态并驱动 AI 审批逻辑
* 同步 Claude、Cursor、Codex、Kimi 等 AI coding 工具状态
* 控制 OLED / 灯光等设备反馈
* 提供本机语音输入和语音 Agent 能力

如果你想开发第三方客户端、查看 BLE 协议、使用硬件 SDK、改按键 / 拨杆 / 灯光 / OLED，或构建自己的自定义 HEX，请查看：

👉 [`protocol / AhaKey Developer Kit`](https://github.com/AhakeyAI/protocol)

如果你想下载官方可烧录固件、查看固件版本说明、校验值或烧录文档，请查看：

👉 [`firmware`](https://github.com/AhakeyAI/firmware)

---

## 它能做什么？

### 1. 设备连接与键盘控制

AhaKey Desktop 可以通过 BLE 连接 AhaKey X1，并配合桌面端完成设备配置和状态同步。

典型能力包括：

* 连接 AhaKey X1
* 配置 4 键 × 多模式映射
* 推送 OLED 内容
* 将 IDE / AI 状态映射到 LED 灯条
* 维护设备与桌面端之间的通信状态

---

### 2. 拨杆审批 AI

AhaKey X1 的物理拨杆是 AI coding agent 的硬件闸门。

典型流程：

```text id="7tc0mo"
拨到自动模式
→ Claude / Cursor / Codex / Kimi 的工具调用可自动放行
→ 拨回手动模式
→ 每个动作交回人工确认
```

后台 agent 会读取拨杆状态，并据此回应各 IDE hook。

设计原则：

> 如果拨杆状态无法读取，默认进入“人工确认”，而不是误放行。
> Fail-safe by design: if the lever cannot be read, it defaults to ask, never allow.

---

### 3. 本机语音 Agent

macOS 端包含本机语音优先的 Agent 能力。

它可以：

* 使用本机语音输入
* 通过 OpenAI 协议兼容方式调用 LLM
* 以用户自己的身份连接生产力工具
* 支持 Feishu / Lark 等工具调用
* 将语音输入、AI 工具调用和桌面工作流连接起来

---

## 客户端与组件

| 组件               | 目录                          | 技术栈                             | 说明                             |
| ---------------- | --------------------------- | ------------------------------- | ------------------------------ |
| macOS 应用         | `ahakeyconfig-mac/`         | Swift · SwiftUI · CoreBluetooth | 主力开发版本，由根目录 `Package.swift` 构建 |
| Windows 应用       | `ahakeyconfig-win-java/`    | Java · JavaFX · Maven           | Windows 桌面客户端                  |
| Windows 应用（旧版）   | `ahakeyconfig-win-python/`  | Python · PyInstaller            | 历史导入基线，主要用于兼容和参考               |
| Linux 应用         | `ahakeyconfig-ubuntu-java/` | Java · JavaFX · Maven           | Ubuntu / Linux 桌面客户端           |
| BLE ↔ TCP bridge | `BLE_tcp_bridge/`           | C#                              | 将 BLE 桥接到本地 TCP，供非原生客户端或调试场景使用 |
| 文档               | `docs/`                     | Markdown                        | 架构、安装、发布、平台支持等说明               |
| 资源               | `assets/`                   | Images / icons / brand assets   | 共享品牌、图标、构建资源等                  |

说明：

* 本仓库定位为 **官方桌面客户端仓库**。
* 本仓库不是 AhaKey Developer Kit 的主入口。
* 本仓库不是官方固件 release 仓库。
* 开发者二创、硬件 SDK、自定义 HEX 构建请优先查看 `protocol`。
* 官方可烧录固件、升级说明、校验值和烧录文档请查看 `firmware`。

---

## macOS 主要能力

macOS 客户端是当前主力实现。

它使用原生 SwiftUI + CoreBluetooth 链路，不依赖 Python / .NET / TCP bridge 作为主链路。

主要能力：

* **Native BLE stack**
  单个签名 `.app` + 常驻 `ahakeyconfig-agent`。

* **AI hooks**
  各 IDE 独立 handler，包括 `ClaudeHookHandler`、`CursorHookHandler`、`CodexHookHandler`、`KimiHookHandler`，共用 `HookSupport` 核心，驱动拨杆审批流程。

* **Voice Agent**
  `VoiceAgent` 模块支持 supervisor + sub-agent 编排、结构化工具调用、独立记忆和 OpenAI 协议兼容的 `LLMClient`。

* **Feishu / Lark**
  通过 `lark-cli` 以用户自己的身份发消息、查联系人，App 不保存飞书凭证。

* **语音输入 HUD**
  基于 Apple Speech 的浮动“按住说话”浮层，可为 IDE、微信等场景做输入中继。

---

## 快速开始

### 下载官方客户端

普通用户建议直接下载 Releases：

👉 [`desktop/releases`](https://github.com/AhakeyAI/desktop/releases)

```text id="d7ouw9"
进入 desktop/releases
→ 下载最新版本
→ 安装桌面客户端
→ 连接 AhaKey X1
→ 开始使用
```

---

### 构建 macOS 客户端

在仓库根目录运行：

```bash id="1q8h3y"
swift build
swift build -c release
```

这会构建 macOS 相关 target，包括 `AhaKeyConfig` 应用可执行文件和 `ahakeyconfig-agent` 辅助进程。

打包成 `.app` 以及其他平台的构建步骤，请查看：

👉 [`docs/installation.md`](docs/installation.md)

---

## 仓库结构

```text id="yp3b0f"
desktop/
├── ahakeyconfig-mac/         # macOS 客户端，Swift + SwiftUI，主力开发
├── ahakeyconfig-win-java/    # Windows 客户端，Java + JavaFX
├── ahakeyconfig-win-python/  # Windows 旧版基线，Python / PySide6
├── ahakeyconfig-ubuntu-java/ # Linux / Ubuntu 客户端，Java + JavaFX
├── BLE_tcp_bridge/           # BLE ↔ TCP 桥接工具
├── Package.swift             # macOS targets 的根 SwiftPM 清单
├── docs/                     # 仓库级文档：架构、安装、发布、平台支持
└── assets/                   # 共享品牌、图标、构建资源
```

如果你看到历史遗留的硬件或固件相关目录，请注意：

* 它们不代表当前公开 SDK 主入口；
* 它们不代表官方固件 release 渠道；
* 新的开发者二创入口请以 [`protocol / AhaKey Developer Kit`](https://github.com/AhakeyAI/protocol) 为准；
* 官方可烧录固件请以 [`firmware`](https://github.com/AhakeyAI/firmware) 为准。

---

## 推荐路径

### 1）我想直接使用官方客户端

```text id="7503xq"
进入 desktop/releases
→ 下载最新版本
→ 安装桌面客户端
→ 连接 AhaKey X1
→ 开始使用
```

入口：

👉 [`desktop/releases`](https://github.com/AhakeyAI/desktop/releases)

---

### 2）我想修改官方桌面客户端

```text id="ks9kvg"
Fork desktop 仓库
→ 新建分支
→ 修改 macOS / Windows / Linux 客户端代码
→ 本地测试
→ 提交 Pull Request
```

适合：

* 修复官方客户端 bug
* 改进 UI
* 优化安装体验
* 增加 macOS / Windows / Linux 适配
* 改进桌面端与设备通信逻辑
* 改进 AI hook、拨杆审批、语音输入等官方能力

入口：

👉 [`desktop`](https://github.com/AhakeyAI/desktop)

---

### 3）我想做第三方客户端、SDK 二创或自定义 HEX

```text id="u6spjv"
进入 protocol
→ 阅读 AhaKey Developer Kit
→ 查看 BLE 协议和 SDK
→ 参考 examples
→ 构建自己的项目或自定义 HEX
```

适合：

* 写第三方 macOS / Windows 客户端
* 读取 AhaKey 设备状态
* 基于 BLE 协议做 workflow
* 使用 SDK 改按键、拨杆、灯光、OLED
* 构建自己的自定义 HEX
* 做 SDK demo

入口：

👉 [`protocol / AhaKey Developer Kit`](https://github.com/AhakeyAI/protocol)

---

### 4）我想查看官方固件版本或烧录官方固件

```text id="2d8jzg"
进入 firmware
→ 查看官方 release notes
→ 核对 SHA256
→ 阅读 flash guide
→ 按官方说明烧录或升级
```

适合：

* 下载官方可烧录固件
* 查看官方固件版本说明
* 查看固件校验值
* 阅读烧录、回退、排障文档

入口：

👉 [`firmware`](https://github.com/AhakeyAI/firmware)

---

### 5）我做了独立项目，想分享给社区

```text id="nwq50v"
进入 awesome-ahakey
→ 按模板提交项目
→ 社区收录
→ 让更多用户看到、学习和 Fork
```

适合：

* 第三方客户端
* 工具脚本
* workflow preset
* SDK demo
* 自定义 HEX 玩法展示
* 按键、拨杆、灯光、OLED 二创
* 使用教程
* 视频 / 图文教程
* 桌面 setup

入口：

👉 [`awesome-ahakey`](https://github.com/AhakeyAI/awesome-ahakey)

---

## 新同学先读

| 文档                                                           | 用途              |
| ------------------------------------------------------------ | --------------- |
| [`docs/repo-layout.md`](docs/repo-layout.md)                 | 了解 desktop 仓库结构 |
| [`docs/architecture.md`](docs/architecture.md)               | 了解桌面端整体架构       |
| [`docs/installation.md`](docs/installation.md)               | 安装、构建和打包说明      |
| [`docs/releases.md`](docs/releases.md)                       | release 相关说明    |
| [`docs/supported-platforms.md`](docs/supported-platforms.md) | 支持平台说明          |

如果你正在找 BLE 协议、SDK 或自定义 HEX 构建说明，请转到：

👉 [`protocol / AhaKey Developer Kit`](https://github.com/AhakeyAI/protocol)

---

## 仓库范围

本仓库应主要保留：

* 官方桌面客户端源码
* 工程文件
* 必要资源
* 桌面端文档
* 构建和发布说明

本仓库不应提交：

* `.app`
* `.dmg`
* `.exe`
* `.class`
* `.o`
* `target/`
* `build/`
* 无关二进制文件
* 私钥、Token、API Key 或个人配置
* 官方完整固件源码
* PCB、Gerber、BOM、生产测试资料或供应链资料

安装包统一通过 GitHub Releases 分发：

👉 [`desktop/releases`](https://github.com/AhakeyAI/desktop/releases)

---

## License

本仓库的开源协议以根目录 [`LICENSE`](LICENSE) 文件为准。

第三方依赖、系统 SDK、工具链、图标、素材或外部资源继续遵循其原始许可证和版权声明。

---

<p align="right"><a href="#top">↑ Back to top</a></p>

---

<a id="en"></a>

<h1 align="center">⌨️ AhaKey Desktop</h1>

<p align="center">
  <strong>The official cross-platform desktop client for AhaKey X1</strong>
</p>

<p align="center">
  Device Connection · Key Mapping · Lever Approval · AI Status Sync · Local Voice Agent
</p>

<p align="center">
  <a href="https://github.com/AhakeyAI/desktop/releases"><img src="https://img.shields.io/github/v/release/AhakeyAI/desktop?include_prereleases&label=release&color=4F46E5" alt="Latest Release"></a>
  <a href="https://github.com/AhakeyAI/desktop/actions"><img src="https://img.shields.io/github/actions/workflow/status/AhakeyAI/desktop/release.yml?label=build" alt="Build"></a>
  <a href="https://github.com/AhakeyAI/desktop/commits/main"><img src="https://img.shields.io/github/last-commit/AhakeyAI/desktop?color=informational" alt="Last Commit"></a>
  <a href="https://github.com/AhakeyAI/desktop/stargazers"><img src="https://img.shields.io/github/stars/AhakeyAI/desktop?style=flat&color=yellow" alt="Stars"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-12%2B-000000?logo=apple&logoColor=white" alt="macOS 12+">
  <img src="https://img.shields.io/badge/Windows-10%2F11-0078D6?logo=windows&logoColor=white" alt="Windows 10/11">
  <img src="https://img.shields.io/badge/Linux-Ubuntu-E95420?logo=ubuntu&logoColor=white" alt="Ubuntu">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/Java-17%2B-007396?logo=openjdk&logoColor=white" alt="Java 17+">
  <img src="https://img.shields.io/badge/Python-3.10%2B-3776AB?logo=python&logoColor=white" alt="Python 3.10+">
</p>

---

## What is AhaKey Desktop?

`AhakeyAI/desktop` is the **official desktop client repository for AhaKey X1 (Vibecoding Keyboard)**.

It connects the AhaKey X1 physical keyboard to your computer and AI coding workflow, including:

* connecting to AhaKey X1
* configuring keys and basic interactions
* reading lever state and driving AI approval logic
* syncing Claude, Cursor, Codex, Kimi, and AI coding states
* controlling OLED / light feedback
* providing local voice input and voice agent features

If you want to build a third-party client, read the BLE protocol, use the Hardware SDK, customize buttons / toggle / lights / OLED, or build your own custom HEX, please start with:

👉 [`protocol / AhaKey Developer Kit`](https://github.com/AhakeyAI/protocol)

If you want to download official flashable firmware, read firmware release notes, checksums, or flashing documentation, please visit:

👉 [`firmware`](https://github.com/AhakeyAI/firmware)

---

## What it does

### 1. Device connection and keyboard control

AhaKey Desktop connects to AhaKey X1 over BLE and helps manage device configuration and status sync.

Typical capabilities include:

* connecting to AhaKey X1
* configuring 4-key × multi-mode mappings
* pushing OLED content
* mapping IDE / AI state to the LED light bar
* maintaining device-to-desktop communication state

---

### 2. Lever-gated AI approval

The physical lever on AhaKey X1 is a hardware gate for AI coding agents.

Typical flow:

```text id="tav9cw"
Flip to auto mode
→ Tool calls from Claude / Cursor / Codex / Kimi can be auto-approved
→ Flip back to manual mode
→ Each action is handed back for human confirmation
```

A background agent reads the lever state and answers IDE hooks accordingly.

Design principle:

> If the lever state cannot be read, it defaults to human confirmation, not accidental approval.
> Fail-safe by design: if the lever cannot be read, it defaults to ask, never allow.

---

### 3. Local voice agent

The macOS client includes a local, voice-first agent.

It can:

* provide local voice input
* call LLMs through an OpenAI-compatible interface
* connect to productivity tools under the user's own identity
* support Feishu / Lark integrations
* connect voice input, AI tool calls, and desktop workflows

---

## Clients and components

| Component          | Directory                   | Stack                           | Notes                                                                  |
| ------------------ | --------------------------- | ------------------------------- | ---------------------------------------------------------------------- |
| macOS app          | `ahakeyconfig-mac/`         | Swift · SwiftUI · CoreBluetooth | Lead implementation; built from the root `Package.swift`               |
| Windows app        | `ahakeyconfig-win-java/`    | Java · JavaFX · Maven           | Windows desktop client                                                 |
| Windows app legacy | `ahakeyconfig-win-python/`  | Python · PyInstaller            | Historical baseline, mainly for compatibility and reference            |
| Linux app          | `ahakeyconfig-ubuntu-java/` | Java · JavaFX · Maven           | Ubuntu / Linux desktop client                                          |
| BLE ↔ TCP bridge   | `BLE_tcp_bridge/`           | C#                              | Bridges BLE to local TCP for non-native clients or debugging scenarios |
| Docs               | `docs/`                     | Markdown                        | Architecture, installation, release, and platform support docs         |
| Assets             | `assets/`                   | Images / icons / brand assets   | Shared brand, icons, and build resources                               |

Notes:

* This repository is the **official desktop client repository**.
* This repository is not the main entry for AhaKey Developer Kit.
* This repository is not the official firmware release repository.
* Developer remixes, Hardware SDK, and custom HEX builds should start from `protocol`.
* Official flashable firmware, update notes, checksums, and flashing docs should start from `firmware`.

---

## macOS highlights

The macOS client is the lead implementation.

It uses a native SwiftUI + CoreBluetooth stack and does not rely on Python / .NET / TCP bridge as the main communication path.

Highlights:

* **Native BLE stack**
  One signed `.app` bundle plus a long-lived `ahakeyconfig-agent`.

* **AI hooks**
  Per-IDE handlers including `ClaudeHookHandler`, `CursorHookHandler`, `CodexHookHandler`, and `KimiHookHandler` share a `HookSupport` core and drive the lever-gated approval flow.

* **Voice Agent**
  The `VoiceAgent` module supports supervisor + sub-agent orchestration, structured tool calling, per-agent memory, and an OpenAI-compatible `LLMClient`.

* **Feishu / Lark**
  Sends messages and resolves contacts via `lark-cli` under the user's own identity. The app does not store Feishu credentials.

* **Voice input HUD**
  A floating push-to-talk overlay backed by Apple Speech, with relay routes for IDEs, WeChat, and other input scenarios.

---

## Quick start

### Download the official client

For normal users, download from Releases:

👉 [`desktop/releases`](https://github.com/AhakeyAI/desktop/releases)

```text id="6gcoh4"
Go to desktop/releases
→ Download the latest version
→ Install the desktop client
→ Connect AhaKey X1
→ Start using it
```

---

### Build the macOS client

Run from the repository root:

```bash id="8zb53m"
swift build
swift build -c release
```

This builds macOS-related targets, including the `AhaKeyConfig` executable and the `ahakeyconfig-agent` helper.

For packaging into a `.app` and other platform build steps, see:

👉 [`docs/installation.md`](docs/installation.md)

---

## Repository layout

```text id="c6vmt4"
desktop/
├── ahakeyconfig-mac/         # macOS client, Swift + SwiftUI, active
├── ahakeyconfig-win-java/    # Windows client, Java + JavaFX
├── ahakeyconfig-win-python/  # Windows legacy baseline, Python / PySide6
├── ahakeyconfig-ubuntu-java/ # Linux / Ubuntu client, Java + JavaFX
├── BLE_tcp_bridge/           # BLE ↔ TCP bridge tool
├── Package.swift             # Root SwiftPM manifest for macOS targets
├── docs/                     # Repo docs: architecture, installation, releases, platforms
└── assets/                   # Shared brand, icons, and build assets
```

If you see historical hardware- or firmware-related directories, please note:

* they are not the current public SDK entry point;
* they are not the official firmware release channel;
* the current developer remix entry is [`protocol / AhaKey Developer Kit`](https://github.com/AhakeyAI/protocol);
* official flashable firmware should be accessed through [`firmware`](https://github.com/AhakeyAI/firmware).

---

## Recommended paths

### 1) I want to use the official desktop client

```text id="dl1qwo"
Go to desktop/releases
→ Download the latest version
→ Install the desktop client
→ Connect AhaKey X1
→ Start using it
```

Entry:

👉 [`desktop/releases`](https://github.com/AhakeyAI/desktop/releases)

---

### 2) I want to modify the official desktop client

```text id="zzj6pm"
Fork desktop
→ Create a branch
→ Modify macOS / Windows / Linux client code
→ Test locally
→ Open a Pull Request
```

Best for:

* fixing official client bugs
* improving UI
* improving installation experience
* adding macOS / Windows / Linux support
* improving desktop-to-device communication
* improving AI hooks, lever approval, voice input, and official client features

Entry:

👉 [`desktop`](https://github.com/AhakeyAI/desktop)

---

### 3) I want to build a third-party client, SDK demo, or custom HEX

```text id="i6dt8u"
Go to protocol
→ Read AhaKey Developer Kit
→ Check BLE protocol and SDK
→ Follow examples
→ Build your own project or custom HEX
```

Best for:

* writing third-party macOS / Windows clients
* reading AhaKey device state
* building workflows on top of the BLE protocol
* using the SDK to customize buttons, toggle, lights, or OLED
* building custom HEX files
* building SDK demos

Entry:

👉 [`protocol / AhaKey Developer Kit`](https://github.com/AhakeyAI/protocol)

---

### 4) I want to check official firmware versions or flash official firmware

```text id="19ogjt"
Go to firmware
→ Read official release notes
→ Verify SHA256
→ Read flash guide
→ Flash or update according to official docs
```

Best for:

* downloading official flashable firmware
* reading official firmware release notes
* checking firmware checksums
* reading flashing, rollback, and troubleshooting docs

Entry:

👉 [`firmware`](https://github.com/AhakeyAI/firmware)

---

### 5) I built an independent project and want to share it

```text id="knnqmb"
Go to awesome-ahakey
→ Submit your project with the template
→ Get listed by the community
→ Help more users discover, learn from, and fork it
```

Best for:

* third-party clients
* utility scripts
* workflow presets
* SDK demos
* custom HEX showcases
* button, toggle, light, and OLED remixes
* tutorials
* video / written guides
* desk setups

Entry:

👉 [`awesome-ahakey`](https://github.com/AhakeyAI/awesome-ahakey)

---

## Start here

| Document                                                     | Purpose                                    |
| ------------------------------------------------------------ | ------------------------------------------ |
| [`docs/repo-layout.md`](docs/repo-layout.md)                 | Understand the desktop repository layout   |
| [`docs/architecture.md`](docs/architecture.md)               | Understand the desktop client architecture |
| [`docs/installation.md`](docs/installation.md)               | Installation, build, and packaging notes   |
| [`docs/releases.md`](docs/releases.md)                       | Release-related documentation              |
| [`docs/supported-platforms.md`](docs/supported-platforms.md) | Supported platform notes                   |

If you are looking for BLE protocol, SDK, or custom HEX build documentation, go to:

👉 [`protocol / AhaKey Developer Kit`](https://github.com/AhakeyAI/protocol)

---

## Repository scope

This repository should mainly contain:

* official desktop client source code
* project files
* required assets
* desktop client documentation
* build and release documentation

This repository should not include:

* `.app`
* `.dmg`
* `.exe`
* `.class`
* `.o`
* `target/`
* `build/`
* unrelated binaries
* private keys, tokens, API keys, or personal config
* full official firmware source
* PCB, Gerber, BOM, production test materials, or supply-chain materials

Installers are distributed through GitHub Releases:

👉 [`desktop/releases`](https://github.com/AhakeyAI/desktop/releases)

---

## License

This repository is licensed according to the root [`LICENSE`](LICENSE) file.

Third-party dependencies, system SDKs, toolchains, icons, assets, and external resources remain under their original licenses and copyright notices.

---

<p align="right"><a href="#top">↑ Back to top</a></p>

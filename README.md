<div align="center">

# ⌨️ AhaKey Desktop

**Native desktop companion for the AhaKey-X1 keyboard — with a built-in voice agent.**

**AhaKey-X1（Vibecoding Keyboard）官方桌面端 · 内置 Voice Agent**

[**English**](#english) &nbsp;·&nbsp; [**简体中文**](#简体中文)

<br/>

<!-- Release & CI -->
<a href="https://github.com/AhakeyAI/desktop/releases"><img src="https://img.shields.io/github/v/release/AhakeyAI/desktop?include_prereleases&label=release&color=4F46E5" alt="Latest Release"></a>
<a href="https://github.com/AhakeyAI/desktop/actions/workflows/release.yml"><img src="https://img.shields.io/github/actions/workflow/status/AhakeyAI/desktop/release.yml?label=build" alt="Release Build"></a>
<a href="https://github.com/AhakeyAI/desktop/commits/main"><img src="https://img.shields.io/github/last-commit/AhakeyAI/desktop?color=informational" alt="Last Commit"></a>
<a href="https://github.com/AhakeyAI/desktop/stargazers"><img src="https://img.shields.io/github/stars/AhakeyAI/desktop?style=flat&color=yellow" alt="Stars"></a>

<br/>

<!-- Platform & Tech -->
<img src="https://img.shields.io/badge/macOS-14.0%2B-000000?logo=apple&logoColor=white" alt="macOS 14+">
<img src="https://img.shields.io/badge/Windows-10%2F11-0078D6?logo=windows&logoColor=white" alt="Windows">
<img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
<img src="https://img.shields.io/badge/SwiftUI-007AFF?logo=swift&logoColor=white" alt="SwiftUI">
<img src="https://img.shields.io/badge/PySide6-3776AB?logo=python&logoColor=white" alt="PySide6">

<br/>

<!-- Activity -->
<a href="https://github.com/AhakeyAI/desktop/issues"><img src="https://img.shields.io/github/issues/AhakeyAI/desktop?color=success" alt="Issues"></a>
<a href="https://github.com/AhakeyAI/desktop/pulls"><img src="https://img.shields.io/github/issues-pr/AhakeyAI/desktop?color=success" alt="Pull Requests"></a>

</div>

---

<a id="english"></a>

## 🇬🇧 English

`AhakeyAI/desktop` is the official source repository for the AhaKey desktop baseline — a companion suite for the AhaKey-X1 keyboard (Vibecoding Keyboard) on Windows and macOS.

The desktop app does two things:

1. **Keyboard control** — connect to the AhaKey-X1 over BLE, configure the 4-key × 3-mode mapping, push OLED art, and reflect IDE state on the LED light bar.
2. **On-device AI workflows** — drive a voice-first agent that runs locally on the user's machine, talks to LLMs, and reaches into productivity tools (e.g. Feishu / Lark) on the user's behalf.

## Highlights

### macOS — actively developed

- **Native BLE stack.** SwiftUI + CoreBluetooth, no Python / .NET / TCP-bridge in the loop. One signed `.app` bundle plus a background `ahakeyconfig-agent` LaunchAgent for LED state pushes after the GUI closes.
- **Voice Agent system.** A `VoiceAgent` Swift module with a supervisor + sub-agent orchestrator (`VoiceAgentOrchestrator`), structured tool-calling, per-agent memory, concurrency limiting, and an OpenAI-compatible `LLMClient`. Sessions persist across launches via `VoiceAgentSessionStore`.
- **Feishu / Lark integration.** Send messages and look up contacts through `lark-cli` under the user's own identity — the app never stores Feishu credentials. Contacts can be aliased locally (`FeishuContactBook`) so sub-agents can resolve names like "智能助手" → `open_id`.
- **Dual workspace.** A root workspace toggle between **IDE 工作台** (classic keyboard config) and **Agent 工作台** (voice agent), backed by a unified design system (`AhaKeyDesignSystem`) and a single onboarding flow (`UnifiedTypelessOnboardingView`).
- **Voice input HUD.** Floating `VoiceInputFloatingHUD` driven by `NativeSpeechTranscriptionService` (Apple Speech) with push-to-talk relay routes for IDEs, WeChat, etc. without losing the holding state on view rebuilds.
- **LLM configuration UI.** `LLMConfigView` surfaces model / endpoint / key settings; provider talks the OpenAI protocol so any compatible backend works.

See `platforms/macos/README.md` and `platforms/macos/client/README.md` for build instructions, BLE protocol docs, and the source map.

### Windows — stable baseline

The Windows client (Python PySide6 + .NET BLE bridge + Swift-equivalent helper) is preserved as the imported baseline. No major refactor this cycle. See `platforms/windows/README.md`.

## Repository layout

```
desktop/
├── platforms/
│   ├── macos/client/      # Swift + SwiftUI client (active)
│   └── windows/           # Windows client baseline
├── docs/                  # Repo-level docs (architecture, releases, layout)
├── scripts/               # Repo-level helper scripts
├── assets/                # Shared brand / build assets
└── releases/              # Release notes (binaries live in GitHub Releases)
```

## Repository scope

This repository stores source code, project files, required assets, and documentation only.

Build artifacts (`.exe`, `.msi`, `.app`, `.dmg`) are **not** committed. Installers are distributed exclusively through GitHub Releases.

## Current status

- macOS client has moved past the post-migration cleanup phase and is in **active feature development** — voice agent, Feishu integration, and the new workbench UI all landed in this cycle.
- Windows client remains on the imported baseline.
- Windows / macOS are intentionally kept in separate platform directories: different runtimes, UI models, and system capabilities.

## Start here

New contributors:

- `docs/repo-layout.md`
- `docs/installation.md`
- `docs/architecture.md`
- `docs/releases.md`
- `platforms/macos/README.md`
- `platforms/macos/client/README.md`
- `platforms/windows/README.md`

---

<a id="简体中文"></a>

## 🇨🇳 简体中文

`AhakeyAI/desktop` 是 AhaKey 官方桌面端 baseline 的源码仓库，对应 AhaKey-X1（Vibecoding Keyboard）在 Windows 与 macOS 上的配套桌面应用。

桌面端做两件事：

1. **键盘控制** — 通过 BLE 连接 AhaKey-X1，配置 4 键 × 3 模式键位映射、推送 OLED 图片、把 IDE 状态映射到灯条上。
2. **设备侧 AI 工作流** — 运行一个本机 voice-first agent，调用 LLM，并代表用户操作生产力工具（飞书 / Lark 等）。

## 主要能力

### macOS — 当前主力开发方向

- **原生 BLE 栈。** SwiftUI + CoreBluetooth，链路里没有 Python / .NET / TCP 桥接。单个签名 `.app` + 一个后台 `ahakeyconfig-agent` LaunchAgent，GUI 关掉后仍能接收 LED 状态推送。
- **Voice Agent 体系。** `VoiceAgent` Swift 模块，supervisor + sub-agent 编排（`VoiceAgentOrchestrator`），结构化工具调用、独立记忆、并发限流，配 OpenAI 协议兼容的 `LLMClient`。会话通过 `VoiceAgentSessionStore` 跨次启动保留。
- **飞书 / Lark 集成。** 通过 `lark-cli` 以用户自己的身份发消息和查联系人，App 不保存飞书凭证。本地可配置联系人别名（`FeishuContactBook`），sub-agent 可以把"智能助手"这种名字解析成 `open_id`。
- **双工作台。** 根工作台支持 **IDE 工作台**（经典键位配置）和 **Agent 工作台**（语音助手）切换，共用 `AhaKeyDesignSystem` 设计系统和 `UnifiedTypelessOnboardingView` 引导流程。
- **语音输入 HUD。** 浮动 `VoiceInputFloatingHUD` 基于 `NativeSpeechTranscriptionService`（Apple Speech），针对 IDE / 微信等场景做了"按住说话"中继路由，View 重建时不会丢失按住状态。
- **LLM 配置界面。** `LLMConfigView` 暴露模型 / endpoint / key 配置，走 OpenAI 协议，任意兼容后端可接。

构建说明、BLE 协议文档和源码索引见 `platforms/macos/README.md` 与 `platforms/macos/client/README.md`。

### Windows — 稳定 baseline

Windows 客户端（Python PySide6 + .NET BLE 桥接 + 辅助 helper）保持迁入时的 baseline，本轮无大规模重构。详见 `platforms/windows/README.md`。

## 仓库结构

```
desktop/
├── platforms/
│   ├── macos/client/      # Swift + SwiftUI 客户端（活跃）
│   └── windows/           # Windows 客户端 baseline
├── docs/                  # 仓库级文档（架构、发布、目录布局）
├── scripts/               # 仓库级辅助脚本
├── assets/                # 共享品牌 / 构建资源
└── releases/              # 发布说明（二进制走 GitHub Releases）
```

## 仓库范围

仓库只保留源码、工程文件、必要资源与文档。

构建产物（`.exe`、`.msi`、`.app`、`.dmg`）**不入库**，安装包统一走 GitHub Releases。

## 当前状态

- macOS 客户端已走过迁入后整理阶段，进入**活跃功能开发**期 —— 本轮新增了 voice agent、飞书集成、新工作台 UI。
- Windows 客户端维持在迁入时的 baseline。
- Windows / macOS 保留独立平台目录：运行时、UI 模型、系统能力差异较大，不混合管理。

## 新同学建议先读

- `docs/repo-layout.md`
- `docs/installation.md`
- `docs/architecture.md`
- `docs/releases.md`
- `platforms/macos/README.md`
- `platforms/macos/client/README.md`
- `platforms/windows/README.md`

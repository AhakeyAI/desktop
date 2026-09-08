# AhaKey Desktop Overview

[English](overview.md) · [简体中文](zh/overview.md) · [Project home](../README.md)

`AhakeyAI/desktop` is the official source monorepo for the **AhaKey-X1 (Vibecoding Keyboard)** desktop suite — the companion software and tooling that turn the physical keyboard into a control surface for AI-assisted coding.

## What it does

1. **Keyboard control** — connect to the AhaKey-X1 over BLE, configure the 4-key × 3-mode mapping, push OLED art, and mirror your IDE's state onto the LED light bar.
2. **Lever-gated AI approval** — the keyboard's physical **lever** is a hardware gate for your AI coding agent. Flip it to *auto* and tool calls from Claude Code / Cursor / Codex / Kimi are auto-approved; flip it back and every action is handed back for manual confirmation. A background agent reads the lever over BLE and answers each IDE hook accordingly — **fail-safe by design: if the lever can't be read, it defaults to *ask*, never *allow*.**
3. **On-device voice agent** *(macOS)* — a local, voice-first assistant that talks to LLMs over the OpenAI protocol and reaches into productivity tools (e.g. Feishu / Lark) under your own identity.

## Clients & components

| Component | Directory | Stack | Notes |
|---|---|---|---|
| **macOS app** | `ahakeyconfig-mac/` | Swift · SwiftUI · CoreBluetooth | Actively developed; built from the root `Package.swift` |
| **Windows app** | `ahakeyconfig-win-java/` | Java · JavaFX (Maven) | Windows desktop client |
| **Windows app (legacy)** | `ahakeyconfig-win-python/` | Python · PyInstaller | Imported baseline (Capswriter-derived) |
| **Linux app** | `ahakeyconfig-ubuntu-java/` | Java · JavaFX (Maven) | Ubuntu desktop client |
| **BLE ↔ TCP bridge** | `BLE_tcp_bridge/` | C# | Bridges BLE to a local TCP socket for non-native clients |

The macOS client is the lead implementation: a native SwiftUI + CoreBluetooth stack (no Python / .NET / TCP bridge in the loop), shipping a signed `.app` plus a background `ahakeyconfig-agent` LaunchAgent that keeps answering IDE hooks and pushing LED state after the GUI closes.

## macOS highlights

- **Native BLE stack** — one signed `.app` bundle + a long-lived `ahakeyconfig-agent`.
- **AI hooks** — per-IDE handlers (`ClaudeHookHandler`, `CursorHookHandler`, `CodexHookHandler`, `KimiHookHandler`) on a shared `HookSupport` core, driving the lever-gated approval flow.
- **Voice Agent** — a `VoiceAgent` module with a supervisor + sub-agent orchestrator, structured tool-calling, per-agent memory, and an OpenAI-compatible `LLMClient`; sessions persist across launches.
- **Feishu / Lark** — send messages and resolve contacts via `lark-cli` under your own identity; the app never stores Feishu credentials.
- **Voice input HUD** — a floating push-to-talk overlay backed by Apple Speech, with relay routes for IDEs, WeChat, etc.

## Plugin SDK

Develop TypeScript plugins with `@ahakey/plugin-sdk`, or embed the Swift `AhaKeyPluginKit` host library. Start with the [SDK overview](../sdks/README.md) and [TypeScript guide](../sdks/typescript/README.md) for a complete plugin tutorial, host APIs, permissions, lifecycle, and runnable macOS demos.

## Build (macOS)

```bash
# from the repo root — the root Package.swift drives the macOS targets
swift build                       # compile all targets
swift build -c release            # release build
```

This produces the `AhaKeyConfig` app executable and the `ahakeyconfig-agent` helper. See [`docs/installation.md`](installation.md) for packaging into a `.app` and the other platforms' build steps.

## Repository layout

```
desktop/
├── ahakeyconfig-mac/         # macOS client — Swift + SwiftUI (active)
├── ahakeyconfig-win-java/    # Windows client — Java
├── ahakeyconfig-win-python/  # Windows client — Python / PySide6 (legacy baseline)
├── ahakeyconfig-ubuntu-java/ # Linux client — Java
├── BLE_tcp_bridge/           # BLE ↔ TCP bridge — C#
├── Package.swift             # Root SwiftPM manifest for the macOS targets
├── sdks/                     # Plugin SDKs, guides, and examples
├── docs/                     # Repo-level docs (architecture, BLE protocol, releases)
└── assets/                   # Shared brand / build assets
```

## Repository scope

Source, project files, required assets, and docs only. **Build artifacts should not be committed** — avoid checking in `.app` / `.dmg` / `.exe` / `.class` / `.o` (and build dirs like `*/target/`). Installers are distributed exclusively through [GitHub Releases](https://github.com/AhakeyAI/desktop/releases).

## Start here

- [`docs/repo-layout.md`](repo-layout.md) · [`docs/architecture.md`](architecture.md) · [`docs/ble-protocol.md`](ble-protocol.md)
- [`docs/installation.md`](installation.md) · [`docs/releases.md`](releases.md) · [`docs/supported-platforms.md`](supported-platforms.md)

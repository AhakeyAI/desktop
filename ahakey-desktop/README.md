# AhaKey Studio: Rust client

Rust + Tauri 2 + React client, version 1.1.5. The client is a separate subproject;
it does not replace the Java, Swift or bridge source trees.
Windows x64 is the tested distribution target. macOS/Linux adapters exist but
their native packaging, permissions and hardware behavior still need validation.
This is a community client for hardware by [AhaKey](https://github.com/AhakeyAI),
not an official replacement for the original desktop suite.

## Companion firmware

The [1.1.5 community Release](https://github.com/lgcyaxi/AhakeyAI/releases/tag/ahakey-studio-1.1.5)
also offers **unofficial experimental firmware 0.1.17 for AhaKey X1 (CH582M)**.
It adds simultaneous USB/two-BLE links, single-destination lever routing,
bonded reconnect recovery and battery-only screen/light standby. The maintainer
reports stable dual-host use; interoperability with every host is not guaranteed.
Firmware and client versions are independent. No firmware is flashed by this app.

Flashing may lose input or pairing, or require recovery. Read the
[firmware guide](https://github.com/lgcyaxi/AhakeyAI/blob/main/ahakey-desktop/FIRMWARE.md)
and keep the official recovery HEX before proceeding. Binary distribution in
the fork Release is permitted for personal, noncommercial research under
[AhaKey's written permission](https://github.com/AhakeyAI/desktop/issues/63#issuecomment-5653215712).
Controlled firmware source and schematics are not part of this project.

## Features

- Four editable profiles for Claude Code, Claude Desktop, Codex CLI and ChatGPT
  App, with four physical key assignments and firmware-dependent lighting.
- Windows USB auto-detection and read-only battery/profile/brightness information,
  independent of Bluetooth connection management. Information comes from one
  confirmed transport at a time; disconnect clears stale USB values.
- Native Bluetooth using WinRT/CoreBluetooth/BlueZ. Connect requires a valid
  device response; Windows commands request an encrypted link. Complete system
  pairing before using protected firmware services.
- Capability-gated USB/BLE routing configuration for compatible firmware:
  fixed upper/lower BLE slots, with USB replacing the upper target while attached,
  or preserve the approval lever. Slot labels and connection diagnostics are
  separate from pairing; pairing resets in the client require USB.
  Unsupported firmware does not receive fabricated successful-save feedback.
  Concurrent links require compatible device firmware; they are not implemented
  by the client alone.
- Voice-key listening defaults on without recording. Explicitly disabling it
  is remembered; corrupt settings do not trigger automatic listener startup.
  Press/hold and toggle modes are supported.
- WeChat and Windows dictation use their external shortcuts. They do not expose
  reliable recording-state readback; end an out-of-sync input-method popup
  manually before resuming. The client does not invent timing-based state.
- Local SenseVoice Small INT8 via sherpa-onnx. Runtime is bundled on Windows;
  weights download/import is opt-in. Local audio is not uploaded.
- Optional Doubao streaming recognition with user-provided API credentials.
  Windows local/cloud captions follow the target window's monitor/work area.
- Image crop/fit/RGB565 preview and export, plus extensible quota cards for
  MiniMax, GLM, Kimi, Codex and custom HTTPS data. Provider credentials remain on
  the host. On-device image/card upload is not implemented in this release.
- Tray provider/profile/caption actions; an optional loopback Hook-event
  receiver. Hooks never auto-approve requests or edit external harness settings.

USB input needs no BLE pairing or companion app, but the keyboard must select
USB as its input target. Voice recognition still needs the receiving computer's
listener/input method. Full profile/light writes currently use BLE; USB supports
information and routing controls. Firmware status 1.0 may be a compatibility
field, not its actual release version.

## Build and test on Windows

Install Node.js 22+, pnpm 10, stable Rust, MSVC Build Tools, Windows SDK and
WebView2. From this subproject:

```powershell
pnpm install --frozen-lockfile
$env:SHERPA_ONNX_LIB_DIR = & .\crates\speech\scripts\prepare-runtime.ps1
pnpm test
pnpm build
cargo test --locked --manifest-path src-tauri/Cargo.toml
cargo test --locked --manifest-path crates/ble/Cargo.toml
cargo clippy --locked --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings
.\scripts\build-windows.ps1
```

Run the executable inside the complete output directory; all four native ASR
DLLs and license notices must remain beside it. The build script never installs,
signs, publishes, or stops another app. No firmware source or HEX is needed to
build this client. Firmware-specific features remain capability-gated.

Windows distribution may name the launcher AhaKeyStudio.exe. Do not run it
alongside the Java client or another preview's voice listener.
The production application identity is ai.ahakey.studio. On first launch only,
validated settings from the known previous preview identities are copied if no
production settings exist. Preview files and explicit listener-off choices are
preserved. Credentials are not copied between identities; reconfigure those
explicitly. Import existing models explicitly rather than overwriting preview data.

## Verification boundary

### macOS app and menu-bar icons

Use an application bundle for the Dock/Finder icon, not the bare Cargo executable.
On your Mac, first prepare the matching native speech libraries as described in
the [speech guide](crates/speech/README.md), setting `SHERPA_ONNX_LIB_DIR`.
Then run from this directory:

```sh
pnpm install --frozen-lockfile
pnpm desktop:bundle
open 'src-tauri/target/release/bundle/macos/AhaKey Studio.app'
```

The macOS config embeds the existing ICNS app icon and usage descriptions.
The menu bar has a separate monochrome template icon, with contrast supplied
by macOS in light/dark mode. Failure to create the tray now reports a startup
error instead of silently skipping it. `desktop:build` remains an explicitly
unbundled developer build, not a macOS installer.

This local-build path is not a claim of portable distribution: signed native
dylib embedding, notarization and clean-machine macOS acceptance remain pending.
Do not publish or copy the app to another machine assuming those steps are done.

### Acceptance limits

Automated checks cover protocol frames, USB and BLE source selection, settings,
caption placement, provider parsers and key-edge state. A separate known-answer
ASR test accepts explicit local fixtures and never opens a microphone or
downloads weights. USB information has been exercised on hardware on Windows;
three-host concurrency, all host sleep/wake cases and non-Windows acceptance
are not implied by unit tests or a successful build.

See the [BLE](crates/ble/README.md), [speech](crates/speech/README.md) and
[cloud](crates/cloud/README.md) module guides. Mutating IPC is restricted to the
main window; the renderer allows local assets and IPC only. Sensitive credentials
do not belong in configuration exports, source control or device payloads.

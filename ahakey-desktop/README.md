# AhaKey Studio: Rust client

Rust + Tauri 2 + React client, version 1.1.0. The client is a separate subproject;
it does not replace the Java, Swift or bridge source trees.
Windows x64 is the tested distribution target. macOS/Linux adapters exist but
their native packaging, permissions and hardware behavior still need validation.

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
  choose two targets from USB, BLE A and BLE B, or preserve the approval lever.
  Unsupported firmware does not receive fabricated successful-save feedback.
  The client does not implement or guarantee multi-link device firmware.
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

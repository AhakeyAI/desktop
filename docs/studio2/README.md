# AhaKey Studio 2 — Windows alpha proposal

[简体中文](README.zh-CN.md)

A native WPF Windows client for configuring AhaKey X1 keys, display animations and lighting, with in-process USB/Bluetooth and optional assistant integrations. This proposal adds Studio 2 alongside the existing clients; it does not replace the Java client or change macOS packaging.

## Try and build

Use the Windows x64 ZIP attached to the Studio 2 CI run, extract the entire folder and launch `AhaKey Studio.exe`. The published app is self-contained; no .NET installation or separate BLE bridge is needed. Build from source on Windows with the .NET SDK specified in `global.json`:

```powershell
dotnet restore AhaKeyStudio.sln
dotnet build AhaKeyStudio.sln -c Release
dotnet test AhaKeyStudio.sln -c Release --no-build
./Publish-Studio.ps1
```

Output: `artifacts/AhaKeyStudio-win-x64/`. Existing Java/macOS release workflows are unchanged. No firmware image or vendor flashing runtime is distributed. The firmware page says when the optional local package is absent. Choose firmware file validates Intel HEX structure only; actual flashing/reinstall is disabled.

## Product scope

| Area | Implemented behavior |
| --- | --- |
| Keys | Four profile workspaces; K2–K4 record/manual/presets, USB Apply, partial live shortcut read and an immediately armed physical Test window. K1 stays firmware-managed F18 with a Windows host voice action. |
| Display | Local image/GIF library; asynchronous bounded conversion, disposal/compositing, Fit/Crop, 160×80 RGB565 frames, animated converted preview, uniform timing and source-defined fixed profile/state allocation. |
| Lighting | Source-known effects 0–16, runtime preview/off, persistent brightness and nine-event mappings with partial readback comparison. Effect 17 is not enabled. |
| Integrations | Configured assistants on the feedback page, explicit integration setup and feedback opt-in, service/last-event status, deterministic multi-session lighting ownership. |
| Device | In-process Windows BLE and USB, fresh identity/capability gates, reduced polling, compact redacted diagnostics, distinct local/sent/read/physically observed provenance. |
| UI | English, Simplified Chinese and Russian, Light/Dark themes, supplied icon set and aligned photographed key regions. |

Modern enablement targets the audited WindowsContract32 identity: firmware **1.4.8**, protocol **3.2**, model **1**. Live capability checks remain feature-specific; private legacy acceptance receipts do not gate these modern features. Legacy reported `1.0` retains narrower evidence-based support; other firmware variants are not silently treated as 1.4.8.

## Validation and known limits

The implementation was accepted locally on one physical X1/CH582M unit reporting 1.4.8 / 3.2 / capabilities 0x7FF over USB. K2–K4 Apply/readback, focused key testing, runtime lighting, brightness, persistent mapping and real Codex-triggered feedback were exercised. The operator confirmed K1–K4 behavior, display output, brightness and lighting effects. The final K3/K4 Apply/readback used the same already-observed shortcuts; it was not a second post-write key-test observation.

One static image and one actual GIF were uploaded through the normal app. The GIF converted 35 source frames / 4550 ms to eight RGB565 frames at 569 ms, using Codex / Default slots 88–95. All 56 blocks, binding and save acknowledged; metadata matched and the operator confirmed physical animation. Other allocated targets are source/test supported, not all physically exercised.

381 software tests pass. A real-WPF regression repeatedly changes library assets and all four profiles, tests cancellation, preview advancement and invalid imports. The reproduced library stack-overflow was caused by unstable collection/selection notifications and fixed at that source. An independently reported Cursor-only crash could not be reproduced; no separate proven cause is claimed. Crash context/stack reporting was added.

Partial 9D reads are live RAM resources, not full persisted backup; labels and old display pixels cannot be reconstructed. Display overwrite is destructive to prior pixels. A failed/uncertain transaction is not blindly retried. Firmware flashing, factory reset and unknown dialect writes are outside this release. This is an unsigned alpha proposal, not an official stable release.

## Screenshots

These are screenshots of the actual WPF implementation using isolated replay fixtures. Connection/status values in them are **test fixtures**, not evidence of a live hardware session. They illustrate the localized UI; the physical results are described separately above.

![English profiles, dark theme](screenshots/profiles-en.png)

![Chinese key editor, light theme](screenshots/keymap-zh.png)

![Chinese display editor, dark theme](screenshots/display-zh.png)

## Review boundaries

The source snapshot is based on locally accepted checkpoint `339e965`; it is proposed on top of current `eternal-dev`. Private historical command journals, machine/device identifiers, the user's original GIF and restricted firmware binaries are excluded from this proposal. Public packaging adds an explicit missing-package state and excludes firmware files from publication.

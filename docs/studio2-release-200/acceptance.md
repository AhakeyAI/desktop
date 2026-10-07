# Release 2.0.0 acceptance and owner decision

Candidate preparation date: 7 October 2026 (Asia/Shanghai). Stable publication and merge are not authorized until the owner reviews the concrete candidate artifacts and remaining gates.

## Software results

- Release build: zero errors/warnings.
- Full .NET suite: 411/411 (Core 120, Protocol 101, Device 149, Integrations 41). WPF, USB/BLE replay, library/profile replay and feature replay passed locally; package hashes are recorded per exact build and independently checked in CI.
- Native transport classes with fixtures verify BLE/USB 9B, shape/mode/source, duplicate/old sequence, 255→0 rollover and stale session rejection. Explicit 92 after physical P1/cached P2 is verified through the real ProfileActivationRuntime in WPF replay.
- Geometry contract validation, four types of GIF/static assets, allocation boundaries, rejected preflight before erase, cancelled pixel transfer, partial journal, no save after failure and no replay after reconnect have software coverage.
- WPF runtime replay verifies sleep 95 little endian + 04 + readback, task slot ownership/overflow/attention priority, active-mask heartbeat, operation gate yielding and cleanup. It uses an ephemeral fixture integration listener, not a user's IDE hook installation.
- Short/long duration logic verifies repeat suppression, release once, context change and cancellation. EN/RU/ZH WPF controls are rendered with resolved resources. Native physical F18 delivery remains a gate.
- Public MSI/ZIP payloads are extracted/read and every file hash is compared with runtime-manifest.json. SHA256SUMS is regenerated per build. Restricted firmware/WCH assets, tests, fixture files and logs are excluded. Signature is reported honestly as NotSigned.
- Existing single-instance, tray hide/reopen, persistence and startup registration have software checks. These are not substitutes for installed-app lifecycle on a clean VM.

## Physical read-only evidence

A real BLE connection confirmed X1 model 1, firmware 1.4.8, protocol 3.2, capabilities 0x7FF, hardware revision 1 and hardware profile P2 via native 00/9F on 7 October 2026. No setter or firmware flashing was sent. Additional bounded read-only 95/9B confirmed sleep 30 minutes and profile mode 2 / source query 0 / sequence 0. These were reads, not settings changes. The native USB route reported UsbNotFound. Hyper-V has zero available VMs. Current-user code-signing certificate count is zero.

This confirms live BLE identity; it does not confirm physical button input, profile-switch sequence, display uploads, installed-app lifecycle or key behavior.

## Physical / external release gates - not passed

1. Clean Windows 11 x64 VM without .NET/SDK: install MSI, optional shortcuts, launch portable, compare two simultaneous launches, upgrade from alpha.9, uninstall and verify user-data preservation. Verify no foreign process is stopped and active device operations prevent unsafe exit.
2. Real Windows sign-out/sign-in with opt-in startup: verify tray startup and path ownership for installed and portable modes.
3. Real X1 firmware 1.4.8: BLE and USB identity, K2–K4 behavior, especially prior automatic K4 observation discrepancy. Physical button profile changes and Studio activation in alternating order; editor draft retained.
4. Visually confirm static/GIF assets on all types, uploads at allocation boundaries, cancellation/link-loss recovery without unintended replay. No pixel rollback or atomicity is promised.
5. Physical integrations: independent concurrent tasks, attention/error priority, four-slot overflow, 10-second heartbeat, host disappearance with 30-second expiry, mode-off/Exit cleanup, bulk upload priority.
6. Native F18 short/long down/up on the real K1, repeat and foreground/lock/disable/exit cancellation, user-configured actions. Microphone never starts merely by enabling routing.
7. Authorized signing infrastructure was not established. Candidate is unsigned; owner decides whether signing is required and provides authorized access if it is.
8. Owner reviews PR, verified artifact hashes and the above acceptance evidence, then explicitly decides whether merge and stable publication may proceed. No stable release is published by this task.

No firmware was flashed and no VM/hardware check is recorded as passed without evidence. Existing alpha hardware acceptance is historical evidence only.

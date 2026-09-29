# Legacy macOS CPU and Codex compatibility fixes

Base: GitHub `main` at `f9a690a` (2026-09-29). The user requested migration of `37697fb`, `8ab1278`, and the Codex approval compatibility fixes finalized by `53c2220`, before adopting the Runtime architecture.

The migration keeps main's VibeBar integration, firmware flasher, plugin targets, voice services, lighting compatibility detection, command acknowledgements, virtual lever override, and release version injection. It retains the existing Agent/socket architecture; no XPC, WAL, Runtime orchestrator, or new firmware protocol is introduced.

## Behavior

- Static light effects render once in a Canvas. Animated effects run at 5/10 FPS while active, and pause in the background or with Reduce Motion.
- GIF playback updates a native backing layer rather than SwiftUI state. Ordinary previews decode at 320px; the existing larger preview remains available. Frames decode on demand into a cache with a 16MiB cost limit instead of retaining every full-size frame. Playback pauses on window close, minimize, detach, or app inactivity.
- The GUI watches the IDE state directory, including atomic rename writes, rather than reading JSON every 0.5 seconds. Timers only handle exact expiration deadlines and monitoring failure fallback.
- BLE state is reduced into an Equatable snapshot. Repeated identical status frames publish nothing; a changed frame publishes one core snapshot. Mode notifications fire on actual changes. Existing lighting capability checks and status-query waiters remain functional.
- Diagnostics and logs have independent observation stores. RSSI polls only while DeviceInfoView is visible. Raw traffic capture is optional, stops after 15 minutes, and does not publish to the Studio manager. Both permanent and capture logs write on a serial background queue with 5MiB × 3 rotation.
- GUI reconnection uses 4/8/15/30-second backoff. GUI and Agent coordinate BLE ownership with a shared file lock. The previous extra 2/3-second retry paths no longer bypass the backoff.
- Agent shared-state writes coalesce identical fields, using a 30-second mtime touch when necessary. Hook events and virtual lever changes still update the file immediately. Failed file writes/touches invalidate the coalescing baseline so the next response retries. Routine identical status responses no longer emit system logs.
- Agent process detection uses a 15-second CLI snapshot and workspace events, publishing only changes. The Hook watchdog retains active lights while a target process is alive; the migration does not introduce new power-protection settings.
- Codex manual lever writes `on-request`; automatic lever writes `never`. The final byte-preserving TOML scanner refuses ambiguous, duplicate, incomplete, and non-scalar syntax. Both SessionStart and PermissionRequest route through the same tested policy writer.
- AhaKey startup repairs an existing top-level scalar `untrusted` to `on-request`, because Codex may otherwise fail before any Hook can run. This cleanup leaves valid strategies, granular strategies, missing keys and files, nested keys, and unrelated bytes untouched. Manual mode means Codex decides when to request approval; it does not promise a prompt for every command.
- Hook installation maintains the associated Codex trusted hashes, and LaunchAgent rewrite detection compares all ProgramArguments. Built application metadata includes the Git SHA.

The Foundation-only Codex policy writer is in Shared so startup cleanup and the Agent use the same implementation. Both root and macOS-directory Swift manifests include the same Shared and test targets.

## Validation

Automated checks cover actual production BLE parsing and publication counts (100 identical frames produce zero further manager publications or log entries), diagnostics/log isolation, reducer behavior, reconnect intervals, connection locking, log routing and rotation, shared-file coalescing, process detection, watchdog behavior, Hook trust hashes, and both Codex Hook entry points. TOML fixtures cover migration, idempotence, byte preservation and fail-closed behavior, including startup cleanup that preserves automatic and granular policies.

Release builds must pass for both the App and Agent on arm64 and x86_64. Run `swift test` at the repository root and `zsh -n ahakeyconfig-mac/scripts/build.sh` before submitting.

Real keyboard CPU/RSS, lever latency, disconnect/reconnect, and foreground/hidden/closed-window playback still require device testing. Historical CPU figures are not measurements of this candidate. This change does not install an App, change the current machine's Codex config, or restart its Agent during development.

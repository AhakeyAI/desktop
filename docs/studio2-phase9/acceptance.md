# Phase 9 owner acceptance — 2.0.0-alpha.9

Branch: `studio2/phase9-release-runtime`, based on accepted Phase 8 `339e965`.
The accepted Phase 8 branch is unchanged. This is an owner acceptance package,
not a public firmware distribution or a completed clean-machine certification.

## Confirmed evidence

- Real AD1E, firmware 1.4.8 / Windows protocol 3.2: BLE connection, 9D partial
  key readback, K2–K4 writes, lighting, brightness restoration and profile
  2 → 1 → 2 were exercised. No firmware flash occurred.
- The user confirmed all keys worked and observed lighting/brightness changes.
  The observation-only key test captured K2 Ctrl+Enter and K3 Escape. K4's
  final automated capture was Ctrl+Enter instead of expected Backspace;
  the user's physical confirmation is separate evidence, not an automated pass.
- The installed self-contained application connected directly over BLE.
  A real Codex event reached the hidden application and effect 0D received an
  ACK. Full Exit sent neutral 00, received its ACK, unsubscribed notifications,
  closed readers and released the process. No separate BLE bridge was needed.
- The user confirmed closing hides the application. Tray reopen and single
  instance activation were checked. UI smoke also checks hide/reopen, blocked
  firmware without live USB, and interrupted-update recovery visibility.
- Local MSI install and uninstall returned exit 0. Application and Start Menu
  shortcut were removed. All 234 snapshotted user-data files remained unchanged.
  Silent uninstall preserves data. Interactive removal defaults to preserving it.
- EN/RU/ZH and dark-theme settings/firmware captures were reviewed. The bounded
  finish review closed all five findings; this is not hardware certification.

Local evidence is under `validation-artifacts/phase9-*` outside this checkout.
Native Windows identities and private user projects are not committed. The
release manifest records packaged file hashes without user data.

## Remaining acceptance boundaries

- USB GIF regression and final MSI upgrade outcomes are recorded in the release
  verification record alongside this document.
- A clean Windows 11 x64 VM without developer tools is not available. The user
  deferred that check. A self-contained payload and successful local install
  do not prove clean-machine behavior.
- Physical same-version firmware reinstall requires a separate final approval.
  No physical vendor erase/program/recovery success is claimed before that test.
- Startup is opt-in. Hidden startup was exercised by launching `--tray`; an
  actual Windows sign-out/sign-in cycle remains untested.
- Firmware components are detected and offered from the official vendor.
  Installing a missing driver on a clean VM remains unverified.

Keep alpha.9 until these acceptance boundaries are resolved. Do not infer beta
readiness from the number of unit tests or from successful vendor process launch.

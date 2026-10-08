# Phase 9 bounded UI documentation

2026-09-21. Native WPF Operate mode; merge into the incumbent design system, without redesign.

## Scope and disposition

The finish reviewer reported all 5/5 findings closed and SHIP at finding scope. This documentation records that supplied review disposition; it is not a new whole-product audit or firmware acceptance. Real firmware flashing and clean-VM installation remain pending.

The merged sources are SettingsPage.xaml, the firmware section of BleDevicePage.xaml, FirmwareViewModel.cs and TrayLifetime.cs. PRODUCT.md and DESIGN.md retain previous phase entries; the sidecar retains its native-WPF extension format and existing tokens. No HTML/CSS approximation, new palette, typography or layout system was introduced.

## Current interface

Settings retains the language/theme card, adding Windows startup into the tray and unexpected-disconnect notifications. Startup copy explains that the main window stays closed. Advanced remains collapsed. Existing local-project and voice controls continue below the card.

Tray Open/double-click restores the shell. First close explains tray lifetime and provides a remember choice and explicit exit alternative. The native menu keeps connection, physical profile and feedback summaries separate from pause/resume service, Settings and Exit. Busy exit provides Wait and eligible cancellation. This describes the native implementation; the supplied capture set is not a complete tray-menu/dialog visual matrix.

Device & Firmware preserves connection controls first. Installed identity, offered package, component readiness, operation state and readiness action appear after a divider. Setup, cancellation and newer-package update have conditional visibility. RecoveryRequired brings retry and recovery help into the normal view; missing saved-target eligibility keeps retry disabled. Advanced retains technical details, package verification, local HEX inspection and reinstall. Package verification copy is not a claim that an update ran successfully.

## Evidence and limits

The supplied external evidence directory is `D:\dev\ahakey\validation-artifacts\phase9-ui-closed`:

- Settings: `settings-English.png`, `settings-Russian.png`, `settings-Chinese.png`.
- Firmware: `firmware-English.png`, `firmware-Russian.png`, `firmware-Chinese.png`, `firmware-dark.png`.
- Interrupted recovery: `firmware-recovery-offline.png`.
- `checks.txt` records shell hide/tray reopen, blocked firmware without live compatible USB identity and offline recovery without a saved target.

The documentation pass visually inspected the Russian Settings and dark offline-recovery captures and inspected the native sources. The broader 5/5 disposition belongs to the finish reviewer. Captures are UI evidence, not real firmware-write, clean-VM, actual-monitor DPI, screen-reader or high-contrast certification. Historical phase acceptance and restrictions remain intact except for this explicitly bounded UI extension.

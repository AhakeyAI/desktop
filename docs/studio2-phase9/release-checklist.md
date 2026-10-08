# Release handoff

Build with `Publish-Studio.ps1`, then `Build-Installer.ps1` using WiX 3.14.
Version comes from `Directory.Build.props`. Output is a per-user x64 MSI,
self-contained portable ZIP and SHA-256 runtime manifest. The installation
directory contains runtime files, licenses and owner firmware assets; no tests,
logs, PDBs, source fixtures or separate BLE bridge.

## Clean Windows 11 VM check (deferred by user)

1. Start from Windows 11 x64 without .NET, Java, development tools or WCH tools.
2. Install MSI as a normal user. Check Apps entry, Start Menu and optional
   desktop shortcut. Launch without installing .NET.
3. Verify missing WCH components explain how to install them without blocking
   BLE. Exercise vendor driver setup and UAC only with explicit consent.
4. Connect AD1E, close to tray, reopen, opt into login startup and sign in again.
   Confirm hidden startup and a single process. Turn startup off again if desired.
5. Upgrade from the previous candidate; confirm projects/settings remain.
6. Choose Exit, uninstall, verify process/shortcuts/startup entry are gone and
   user data remains. Test explicit data removal only with disposable test data.

Normal BLE routes cover supported lightweight Windows 1.4.8 operations. Display
bulk transfer and firmware require USB. No full configuration/pixel readback,
firmware reflash, or clean-VM pass is implied by the packaged release.

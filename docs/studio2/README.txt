AhaKey Studio 2.0.0-alpha.8 - Windows x64 preview

Extract the complete ZIP and run AhaKey Studio.exe.
No separate .NET runtime or Bluetooth bridge is required.

For source-matched AhaKey X1 firmware 1.4.8 / Windows protocol 3.2:
- Edit and apply K2-K4 over USB; read the current shortcut and test keys.
- Import images/GIFs, preview converted animation and upload to allocated targets.
- Preview lighting, apply brightness and event mappings, enable assistant feedback.
- K1 remains F18; voice actions run on the Windows host.

This public package contains no firmware image or vendor flashing component.
Firmware flashing is disabled. Advanced HEX validation checks file structure;
it does not establish device compatibility or authorize flashing.

Partial readback is not a full backup. Display uploads replace existing pixels.
No automatic retry follows an uncertain write. This is an unsigned alpha build.
See docs/studio2/README.md in the source repository for validation and limits.

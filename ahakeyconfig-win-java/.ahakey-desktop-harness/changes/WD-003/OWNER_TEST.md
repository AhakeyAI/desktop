# WD-003 Owner Formal Test Packet

This packet is for the exact WD-003 formal JAR and the paired CP4D firmware identity only. It is not a release, not installer validation, and not a statement that the physical device has already passed.

## Launch

```powershell
Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\builds\WD-003\20261008T005913928548Z-cecb3e\runtime'; & 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' -cp 'ahakey-studio-1.0.0.jar;lib\*' com.example.ahakey.Main
```

## Preconditions

- Confirm the physical keyboard is the intended X1 unit flashed with CP4D HEX SHA256 `6f9759eb912ec067564c4e63558589ab9732126344d52c2d2a278383119516be`.
- Use the normal USB or BLE connection path and record which one was used.
- Keep a screenshot or logs for every failure. Do not treat the earlier Owner Preview PASS as this formal result.

## Steps

T01 Launch the exact formal JAR from the runtime directory above. Expected: the app opens normally; launch alone does not prove device behavior.

T02 Connect the intended CP4D keyboard and confirm firmware identity. Expected: the device connects, and Owner explicitly confirms the CP4D HEX identity before any write-like step.

T03 Confirm `0x9F` capability gating. Expected: CP4C/CP4D-capable catalog key is read and accepted; if `0x9F` is missing, fails, or returns a non-allowlisted key, Windows keeps legacy behavior and does not use `0x87` or editable `0x97`.

T04 Confirm preserved `0x95` sleep wait time read. Expected: the existing sleep wait time UI still reads a legal value and does not regress.

T05 Confirm `0x97` side-switch readback. Expected: the side-switch Inspector shows current up/down configuration from firmware, with physical position preserved.

T06 Confirm ordinary K1-K4 baseline readback in the current mode. Expected: K1-K4 display the device baseline from `0x87`, including default or empty configs, without breaking the normal visible configuration.

T07 Switch through the remaining modes and wait for background readback. Expected: all four modes x four ordinary keys are read, mode switching does not show stale local defaults, and current-mode data appears quickly.

T08 Save side-switch Custom single key, for example Backspace. Expected: Windows writes via `0x97`, reads back `0x97`, and reports success only after the readback matches.

T09 Save side-switch Custom combination shortcut, for example Ctrl+V. Expected: the payload is preserved as shortcut bytes and readback matches exactly.

T10 Save a short side-switch Custom macro. Expected: the short macro saves and reads back; oversized macro attempts are blocked or clearly reported instead of silently truncated.

T11 Save an ordinary key change and verify `0x87` readback. Expected: Windows writes through existing ordinary-key save flow and reports saved only after affected key readback matches.

T12 Check failure and disconnect behavior. Expected: readback/save mismatch or disconnect shows a visible notice or disabled state, keeps unverified local draft, and logs structured evidence.

T13 Check legacy fallback only if a non-CP4C/legacy firmware device is available. Expected: ordinary keys keep the old local behavior, editable `0x97` is hidden, and Windows does not call `0x87`. If no such device is available, mark this step not executed rather than passing it.

## Return

Return pass/fail/not-executed for every T step, the actual USB/BLE path, the firmware confirmation quote, screenshots for side-switch and K1-K4 readback, and `logs/ahakey-studio.log` for failures.

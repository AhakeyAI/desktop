# WD-004 Owner UAT Pass Evidence

- Captured at: 2026-10-12T15:24:11+08:00
- Change: WD-004
- Candidate commit: 41c034171e60b2d4962b0adbe8f3cffbf80a0436
- Candidate tree: 8618ec2f2b70743dba74c595f89af7f6d49aa647
- Test artifact: .ahakey-desktop-harness/changes/WD-004/builds/20261012T_build_wd004_41c0341/runtime-jar-classpath/ahakey-studio-1.0.0.jar
- Test artifact SHA256: 7832196bf1b2d8e3f2864763e40f69edb1de5ac622b941b0992377939740a4b6

Owner result source from current chat:

> 测试全部通过

Owner-scoped interpretation recorded by DLA:

- WD-004 wired and Bluetooth UAT passed on the candidate JAR.
- Firmware version, sleep wait time, mode switching, and AI runtime light behavior passed in the accepted UAT scope.
- Codex/Cursor RUNNING and DONE behavior passed: running is green, done is red, with firmware interpreting RUNNING=1 and DONE=3.
- Slot binding UI, main display selection, tooltip display, and slot-to-LED explanation passed.
- Yellow PermissionRequest / WAITING remains a residual verification item because Owner did not explicitly confirm a physical PermissionRequest event in the final UAT statement.

Limits:

- This evidence is an Owner UAT result record for WD-004 only.
- It is not an EXE/installer release result.
- It is not physical proof of yellow PermissionRequest / WAITING behavior.

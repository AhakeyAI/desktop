# Owner Approval — WD-001

Time: 2026-09-28 Asia/Shanghai

Owner approval text:

> 批准 WD-001 Contract。请 DLA 按 .ahakey-desktop-harness/changes/WD-001/CONTRACT.md 登记 approve，并派发 DIB 仅在 allowed_paths 内实现 CP3A “睡眠等待时间”Windows 内部联调功能。

Approved contract:

- `.ahakey-desktop-harness/changes/WD-001/CONTRACT.md`
- `.ahakey-desktop-harness/changes/WD-001/change.json`
- `.ahakey-desktop-harness/changes/WD-001/REFERENCES.json`

Scope constraint:

DIB may modify only the allowed_paths recorded in WD-001 change.json. Firmware and eternal remain read-only references. Windows must not send `0x04 save_config` for the CP3A sleep wait time setting.

# WD-002 Firmware Discovery Record

Created at: 2026-10-02T20:06:00+08:00
Role: DLA
Status: DISCOVERY_COMPLETE / PLANNED_CHANGE_ONLY

## Read-Only Source

Firmware repo root: `C:\Users\20825\Desktop\vibe-code`

Firmware git HEAD observed by DLA:
`bd1ea87e10939fd6f738b599a4c66ba3264acf70`

This record is a Windows-side evidence index. Firmware files were read only.

## Discovery Basis

- Firmware `AGENTS.md`
- `.agents/skills/ahakey-firmware-harness/SKILL.md`
- `.agents/skills/ahakey-module-lead/SKILL.md`
- `.ahakey-harness/project-state.yaml`
- `.ahakey-harness/workstream-registry.yaml`
- `.ahakey-harness/module-registry.yaml`
- `.ahakey-harness/workstreams/X1-INPUT-CONTROL/STATE.yaml`
- `.ahakey-harness/evidence/checkpoints/X1-INPUT-CONTROL/CP4A/20261002T084039/gate-receipt.json`
- `.ahakey-harness/evidence/checkpoints/X1-INPUT-CONTROL/CP4A/candidate-readiness/20261002T083947/candidate-readiness.md`
- `.ahakey-harness/evidence/stage-b/X1-INPUT-CONTROL-CP4A-20261002-integrated-design-revision.md`
- `.ahakey-harness/evidence/design-reviews/X1-INPUT-CONTROL-CP4A-20261002-stage-c-design-review-pass.md`
- `.ahakey-harness/evidence/owner-uat/X1-INPUT-CONTROL/CP4A/CP4A-OWNER-UAT-BRIEF.md`

## Selected Candidate

One clear new formal Firmware gate was found after Windows-consumed WD-001 /
Device Info / Firmware Identity work:

- Workstream: `WS2 / X1-INPUT-CONTROL`
- Checkpoint: `CP4A`
- Title: `Mode sync and display status foundation`
- Firmware state: `OWNER_UAT / candidate_ready`
- Gate result: `PASS`
- Candidate commit: `bd1ea87e10939fd6f738b599a4c66ba3264acf70`
- HEX: `.ahakey-harness/evidence/builds/ws2-cp4a-mode-sync-display-status/HID_Keyboard_582m_vibe_coding.hex`
- HEX SHA256: `8E11F2B526E9239A67C5199AFF88EBBED875BDC9CB3DF0EB5592979E5F021867`

## Protocol Summary

- Uses existing `0x00` status readback.
- Uses existing `0x92` Desktop-to-keyboard mode set.
- No new Firmware opcode is introduced.
- Desktop mode set success requires `0x92 OK` and follow-up `0x00` readback
  matching the requested mode.
- Failure, timeout, disconnect or readback mismatch returns Windows visible
  state to keyboard-authoritative mode.
- USB and BLE parity is part of the Firmware Owner UAT requirement.

## Intake Outcome

WD-002 is prepared as `PLANNED / CHANGE` for CP4A Mode Sync + Display Status.

WD-001 Recovery remains the only active implementation. WD-002 has not entered
IMPLEMENT, BUILD, VERIFY or Owner real-device test.

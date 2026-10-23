# WD-002 Preview closure node - 2026-10-04

Node name: WD-002_PREVIEW_PASS_FORMAL_DEFERRED

## Owner outcome

- Owner confirmed the original Preview failure is fixed.
- Original failure: when Windows initiated a mode switch, the Windows UI briefly bounced back to the old mode before returning to the new mode.
- Latest tested artifact: `.ahakey-desktop-harness/previews/WD-002/preview-20261004T035500727825Z-83f2e1/runtime/ahakey-studio-1.0.0.jar`
- Preview result record: `.ahakey-desktop-harness/evidence/owner-preview-feedback-WD-002-ui-bounce-pass-20261004.md`
- Harness Preview result: PASS recorded with `preview-result`.

## Deferred follow-up

- Follow-up: keyboard-initiated mode switch makes Windows UI follow slowly, roughly 4-5 seconds.
- Owner decision: do not fix this in the current batch; it is slow but usable.
- Deferred record: `.ahakey-desktop-harness/evidence/owner-decision-WD-002-defer-keyboard-initiated-mode-latency-20261004.md`
- Technical diagnosis summary: Java applies status quickly after receiving it; current delay matches the 5-second polling fallback. Firmware local mode switch does not actively push status to desktop, and the BLE bridge currently consumes recognized status notifications instead of pushing `DeviceInfoResp 0x83` to Java.

## Workflow boundary

- This node is Preview PASS only.
- Owner explicitly did not request Fresh Review, Formal Candidate, Release Batch, or installer validation.
- `desktop.py close` was not completed because formal close requires legacy/formal test packet records that were not part of this Preview-only lane.
- `desktop.py suspend` was not completed because the harness requires Git save/candidate handling for current dirty production files, and no automatic Git add/commit/reset was authorized.

## Practical next state

- WD-002 functional Preview target is accepted by Owner.
- Keyboard-initiated mode latency is recorded as deferred.
- It is safe for Owner to start the next feature from a product/testing standpoint.
- If formal delivery is later needed, WD-002 must go through the formal candidate/delivery path rather than reusing this Preview PASS as Release/UAT PASS.

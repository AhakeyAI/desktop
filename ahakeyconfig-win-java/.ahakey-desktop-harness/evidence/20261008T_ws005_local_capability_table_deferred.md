# Deferred Windows Scope: WS005 local firmware capability table

Date: 2026-10-08

Owner decision:

- Do not expand WD-004 into a full local firmware capability table.
- WD-004 should first finish the WS3 CP1 AI runtime/light presentation adaptation with a simple old/new firmware gate.
- A later WS005 should consolidate the local Windows capability table and cover all previous firmware stages where old/new firmware require different Windows behavior.

Current WD-004 narrow rule:

- Treat firmware with valid 0x9F catalog key `x1-c582-hw1-p1-1.0.0-r001` as the known new firmware path for WS3 CP1 AI runtime presentation.
- Treat old firmware, missing 0x9F, failed 0x9F, or unknown catalog key as legacy/unsupported for WS3 CP1 MULTI device writes.
- Legacy/unsupported firmware may still use local UI state and legacy SINGLE 0x90 behavior where already supported, but Windows must not send 0x98/0x99/0x9A for WS3 CP1.

WS005 intended scope:

- Define one Windows-owned local capability resolver instead of scattered per-feature helpers.
- Record all accepted firmware-stage capability differences from WS1, WS2, and WS3.
- Map firmware identity to feature availability and UI behavior.
- Preserve the rule that Desktop must not guess new capabilities from version text or trial writes.
- Keep unknown catalog keys fail-closed for advanced device writes while preserving legacy behavior.

Firmware evidence to reconcile in WS005:

- WS1 Connectivity/Power:
  - 0x95 official self-persisting sleep wait time query/set.
  - 0x86 retired for sleep wait time.
  - lifecycle/safety presentation priority above mode and AI/task display.
- WS2 Input/Control:
  - 0x9F catalog key identity and legacy 0x00 firmware main/sub fallback.
  - 0x96 Voice onboarding state/suppress.
  - 0x97 side-switch configuration.
  - 0x87 ordinary-key readback.
  - legacy firmware keeps old local ordinary-key behavior and traditional side-switch facts.
- WS3 AI Workflow Presentation:
  - 0x90 legacy SINGLE AI state.
  - 0x98 SINGLE/MULTI mode set.
  - 0x99 v1 complete four-slot MULTI snapshot.
  - 0x9A compatibility ACK only.

Non-goals for WD-004:

- No general release catalog UI.
- No firmware upgrade/recovery decisions.
- No full capability matrix migration.
- No retroactive rewrite of existing WD-001/WD-002/WD-003 implementation behavior except the narrow WS3 CP1 gate needed by WD-004.

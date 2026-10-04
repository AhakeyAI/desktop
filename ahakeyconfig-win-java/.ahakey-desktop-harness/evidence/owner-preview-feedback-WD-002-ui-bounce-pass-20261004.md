# WD-002 Owner Preview feedback - UI bounce fixed

Date: 2026-10-04
Change: WD-002
Preview token: preview-20261004T035500727825Z-83f2e1
Artifact: .ahakey-desktop-harness/previews/WD-002/preview-20261004T035500727825Z-83f2e1/runtime/ahakey-studio-1.0.0.jar

Owner result:

- PASS. Owner reported that the Windows-initiated mode switch bounce is fully resolved.
- Tested behavior: when switching to a new mode from the Windows upper-computer UI, the UI no longer briefly returns to the old mode before entering the new mode.
- Owner wording: "现在这个问题已经被彻底解决，测试非常 OK。"

Scope meaning:

- This record closes the original Preview failure targeted by the v1.3 Preview Fix fast lane.
- This is an Owner Preview result only. It is not a Formal Candidate, Release Batch, EXE installer result, or broad regression pass.

Known follow-up observed during the same session:

- Keyboard-initiated mode switch still updates the Windows UI slowly, commonly around 4-5 seconds.
- Owner decided to defer that follow-up for now because the current behavior is usable.
- The deferred behavior is tracked separately and must not be treated as a blocker for closing the Windows-initiated UI bounce Preview Fix.

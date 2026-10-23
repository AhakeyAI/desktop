# Owner Approval: WD-004

Date: 2026-10-08

Owner approved moving WD-004 from CHANGE to implementation after the WS3 CP1 grilling and scope narrowing.

Owner message summary:

- The remaining WD-004 decisions are sufficiently clear.
- Implementation may start directly.
- Cursor hook changes should reference the already-existing PR AhakeyAI/desktop#78.
- WD-004 should keep the simple old/new firmware judgment for the AI runtime/light work.
- Full local firmware capability table and all prior WS1/WS2/WS3 old/new behavior mapping remain deferred to WS005.

PR #78 implementation facts to reference:

- Cursor hook should explicitly allow only automatic mode.
- Manual, unavailable, timeout, or disconnected state should defer to Cursor native permissions instead of returning deny.
- Hook runtime should not keep rewriting Cursor global permissions.
- Cleanup of old generated Cursor permissions should be conservative and only remove exact AhaKey-generated legacy files.

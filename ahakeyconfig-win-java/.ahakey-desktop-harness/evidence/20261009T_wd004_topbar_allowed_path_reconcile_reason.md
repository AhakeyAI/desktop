# WD-004 DLA reconcile reason - TopBar allowed path machine sync

DLA decision: perform a governance-only WD-004 contract reconcile to synchronize the machine `allowed_paths` with the existing revision 3 Owner-approved boundary.

Reason:

- `TopBar.java` is already explicitly listed in `.ahakey-desktop-harness/evidence/20261009T_wd004_hook_task_grill_reconcile_reason.md` as an allowed production path.
- DIB's revision 3 implementation requires `TopBar.java` because Hook 管理 lives under the existing top-right "更多" entry.
- The guard blocker is caused by `change.json.allowed_paths` not carrying the explicit TopBar path. This is a record synchronization gap, not a product or implementation expansion.
- Updating `change.json.allowed_paths` and then running formal `contract-reconcile` preserves Harness traceability and binds the corrected machine scope to a new effective approval.

Scope of this reconcile:

- Add `src/main/java/com/example/ahakey/view/TopBar.java` to WD-004 `allowed_paths`.
- Do not add any new production behavior.
- Do not modify Harness rules, guard code, seals, or product source.
- Do not build, install Hooks, write device state, or perform Git write actions.

Expected next step:

- If the guard becomes clean, freeze DIB implementation evidence through the normal submit path or equivalent legal transfer, then continue DLA actual diff review.

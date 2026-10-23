# WD-004 Owner/DLA scope record - TopBar allowed path sync

Owner asked DLA to handle the WD-004 revision 3 DIB submit blocker where `src/main/java/com/example/ahakey/view/TopBar.java` is still detected by the guard as outside activation scope.

Relevant facts:

- WD-004 revision 3 DLA reconcile reason explicitly included `src/main/java/com/example/ahakey/view/TopBar.java` in the effective DIB boundary.
- The implementation change in `TopBar.java` is the top-right "更多 -> Hook 管理" UI entry and is required by revision 3 Owner scope.
- `desktop.py guard-status --id WD-004 --role DLA` currently blocks immutable origin/scope/governance only on `TopBar.java`.
- The machine `change.json.allowed_paths` list did not include `TopBar.java`, even though the revision 3 reason record did.

Owner requested DLA to legally handle this guard blocker if possible, without changing Harness rules, without build, without installing Hooks, without device writes, and without Git stage/commit/push.

Decision:

- This is not a new product scope expansion and not a new implementation requirement.
- The WD-004 task record should synchronize its machine `allowed_paths` with the already-approved revision 3 textual boundary by adding `src/main/java/com/example/ahakey/view/TopBar.java`.

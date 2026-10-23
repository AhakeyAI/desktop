# REVIEW before executing. This script stages ONLY listed paths and never commits.
# Stop other writers. Do not execute if the list includes private or unrelated material.
Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop'
$existing = @(git -c core.quotePath=false diff --cached --name-only)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Git index' }
if ($existing.Count -gt 0) { throw 'Index already contains staged changes. Review them separately; do not auto reset.' }
$paths = @(
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-004/CONTRACT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-004/EXECUTION_REPORT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-004/IMPLEMENTATION_RECEIPT.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-004/REFERENCES.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-004/REVIEW.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-004/builder_submission.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-004/guard-origin.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-004/review_pack.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-004/reviews/20261009T042219327516Z-1446c9/ACTUAL_DIFF.txt',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-004/reviews/20261009T042219327516Z-1446c9/FRESH_REVIEW_DLA_INDEPENDENT_20261009T0448476726623Z.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-004/start-fingerprint.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/20261008T_ai_runtime_multi_codex_owner_record.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/20261009T_wd004_topbar_allowed_path_owner_scope.md',
    'ahakeyconfig-win-java/pom.xml',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/app/StudioController.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/model/AiRuntimeDisplayMode.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/model/AiRuntimeSession.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/model/AiRuntimeSlotBinding.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/model/AiRuntimeSlotState.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/model/CodexSession.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/protocol/AhaKeyProtocol.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/AiRuntimeDisplayService.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/BleManager.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/CodexSessionDiscoveryService.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/CursorSessionDiscoveryService.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/HookDispatchServer.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/HookInstaller.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/util/AiRuntimeStore.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/InspectorPane.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/TopBar.java'
)
git --literal-pathspecs add -- $paths
if ($LASTEXITCODE -ne 0) { throw 'git add failed; stop and inspect, do not force-add' }
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Staged whitespace/conflict checks failed' }
git --no-pager diff --cached --stat
# Inspect actual staged diff, then Owner explicitly runs (not executed here):
# git commit -m 'WD-004 candidate pending Owner UAT'
# Check $LASTEXITCODE immediately after any Owner-run git commit, before writing evidence.
# An empty staged diff may mean an existing candidate is already saved: inspect/reuse it,
# do not claim that a new commit was created. No empty or duplicate commit is required.
# Record 'created new commit' vs 'reused verified existing commit' truthfully, with full hash.
# Git hooks may run in a user commit. Recheck candidate afterwards; no auto push.

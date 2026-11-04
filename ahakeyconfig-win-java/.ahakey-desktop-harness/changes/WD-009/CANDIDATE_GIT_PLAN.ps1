# REVIEW before executing. This script stages ONLY listed paths and never commits.
# Stop other writers. Do not execute if the list includes private or unrelated material.
Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop'
$existing = @(git -c core.quotePath=false diff --cached --name-only)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Git index' }
if ($existing.Count -gt 0) { throw 'Index already contains staged changes. Review them separately; do not auto reset.' }
$paths = @(
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-009/CONTRACT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-009/EXECUTION_REPORT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-009/IMPLEMENTATION_RECEIPT.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-009/REFERENCES.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-009/REVIEW.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-009/builder_submission.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-009/guard-origin.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-009/independent-review-r4/REVIEW.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-009/preserved_foreign_inputs.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-009/review_pack.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-009/reviews/20261103T072512844665Z-017c7c/ACTUAL_DIFF.txt',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-009/start-fingerprint.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/20261101-wd009-five-items-owner.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/20261103-wd009-hook-fix-owner.md',
    'ahakeyconfig-win-java/pom.xml',
    'ahakeyconfig-win-java/scripts/ble-driver-fixes.patch',
    'ahakeyconfig-win-java/scripts/test-ble-driver.ps1',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/app/StudioController.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/model/DeviceStatus.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/model/StudioState.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/AiRuntimeDisplayService.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/BleManager.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/CursorSessionDiscoveryService.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/DeviceSyncService.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/HookDispatchServer.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/HookInstaller.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/KeySimulationService.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/KimiAhaKeyBridge.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/SocketServer.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/CanvasController.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/InspectorPane.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/TopBar.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/wd009/ApprovalFactsChecks.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/wd009/CursorWaitingChecks.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/wd009/HookManagementChecks.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/wd009/KimiConsumerFixture.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/wd009/KimiRoutingChecks.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/wd009/Wd009HookUiChecks.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/wd009/Wd009UiChecks.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/wd009/replay_kimi_consumer.py'
)
git --literal-pathspecs add -- $paths
if ($LASTEXITCODE -ne 0) { throw 'git add failed; stop and inspect, do not force-add' }
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Staged whitespace/conflict checks failed' }
git --no-pager diff --cached --stat
# Inspect actual staged diff, then Owner explicitly runs (not executed here):
# git commit -m 'WD-009 candidate pending Owner UAT'
# Check $LASTEXITCODE immediately after any Owner-run git commit, before writing evidence.
# An empty staged diff may mean an existing candidate is already saved: inspect/reuse it,
# do not claim that a new commit was created. No empty or duplicate commit is required.
# Record 'created new commit' vs 'reused verified existing commit' truthfully, with full hash.
# Git hooks may run in a user commit. Recheck candidate afterwards; no auto push.

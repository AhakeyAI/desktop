# REVIEW before executing. This script stages ONLY listed paths and never commits.
# Stop other writers. Do not execute if the list includes private or unrelated material.
Set-Location -LiteralPath 'C:\Users\20825\.codex\worktrees\wd010-zxy-20261105'
$existing = @(git -c core.quotePath=false diff --cached --name-only)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Git index' }
if ($existing.Count -gt 0) { throw 'Index already contains staged changes. Review them separately; do not auto reset.' }
$paths = @(
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-011/CONTRACT-ACR4.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-011/CONTRACT-BLE-RECOVERY.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-011/CONTRACT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-011/EXECUTION_REPORT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-011/IMPLEMENTATION_RECEIPT.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-011/REFERENCES.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-011/REVIEW.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-011/builder_submission.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-011/evidence/20261109-ble-fix-owner-authorization.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-011/fresh-review/REVIEW-BLE-R4-20261109.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-011/guard-origin.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-011/review_pack.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-011/reviews/20261109T031214165974Z-81858f/ACTUAL_DIFF.txt',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-011/start-fingerprint.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/20261106-wd011-owner-authorization.md',
    'ahakeyconfig-win-java/scripts/ble-driver-fixes.patch',
    'ahakeyconfig-win-java/scripts/test-ble-driver.ps1',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/app/StudioController.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/model/OledResourceState.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/protocol/K1RouteProtocol.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/protocol/LosslessUploadProtocol.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/BleManager.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/CommandSessionArbiter.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/DeviceSyncService.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/DisplayConfigService.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/LosslessUploadService.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/OledResourceStore.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/OledUploadService.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/util/LosslessResourceEncoder.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/wd011/BleStatusRecoveryChecks.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/wd011/CommandSessionChecks.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/wd011/LosslessChecks.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/wd011/LosslessUiChecks.java',
    'ahakeyconfig-win-java/src/test/resources/wd011/acr4/expected.json',
    'ahakeyconfig-win-java/src/test/resources/wd011/acr4/noise8.cp2',
    'ahakeyconfig-win-java/src/test/resources/wd011/acr4/pattern12.cp2',
    'ahakeyconfig-win-java/src/test/resources/wd011/acr4/pattern8.cp2'
)
git --literal-pathspecs add -- $paths
if ($LASTEXITCODE -ne 0) { throw 'git add failed; stop and inspect, do not force-add' }
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Staged whitespace/conflict checks failed' }
git --no-pager diff --cached --stat
# Inspect actual staged diff, then Owner explicitly runs (not executed here):
# git commit -m 'WD-011 candidate pending Owner UAT'
# Check $LASTEXITCODE immediately after any Owner-run git commit, before writing evidence.
# An empty staged diff may mean an existing candidate is already saved: inspect/reuse it,
# do not claim that a new commit was created. No empty or duplicate commit is required.
# Record 'created new commit' vs 'reused verified existing commit' truthfully, with full hash.
# Git hooks may run in a user commit. Recheck candidate afterwards; no auto push.

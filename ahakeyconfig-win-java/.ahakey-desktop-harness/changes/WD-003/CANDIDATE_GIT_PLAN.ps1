# REVIEW before executing. This script stages ONLY listed paths and never commits.
# Stop other writers. Do not execute if the list includes private or unrelated material.
Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop'
$existing = @(git -c core.quotePath=false diff --cached --name-only)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Git index' }
if ($existing.Count -gt 0) { throw 'Index already contains staged changes. Review them separately; do not auto reset.' }
$paths = @(
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-003/CONTRACT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-003/EXECUTION_REPORT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-003/FRESH_REVIEW_BUILD_ROUND_9.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-003/IMPLEMENTATION_RECEIPT.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-003/REFERENCES.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-003/REVIEW.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-003/builder_submission.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-003/guard-origin.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-003/review_pack.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-003/reviews/20261007T093900372181Z-fc2e84/ACTUAL_DIFF.txt',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-003/start-fingerprint.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/20261005T175747_input-domain-change-owner-record.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/20261007T170857_wd003_owner_reference_reconcile_authorization.md',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/app/StudioController.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/model/StudioState.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/protocol/AhaKeyProtocol.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/protocol/AhaKeyResponseParser.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/BleManager.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/DeviceSyncService.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/UsbHidTransport.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/InspectorPane.java'
)
git --literal-pathspecs add -- $paths
if ($LASTEXITCODE -ne 0) { throw 'git add failed; stop and inspect, do not force-add' }
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Staged whitespace/conflict checks failed' }
git --no-pager diff --cached --stat
# Inspect actual staged diff, then Owner explicitly runs (not executed here):
# git commit -m 'WD-003 candidate pending Owner UAT'
# Check $LASTEXITCODE immediately after any Owner-run git commit, before writing evidence.
# An empty staged diff may mean an existing candidate is already saved: inspect/reuse it,
# do not claim that a new commit was created. No empty or duplicate commit is required.
# Record 'created new commit' vs 'reused verified existing commit' truthfully, with full hash.
# Git hooks may run in a user commit. Recheck candidate afterwards; no auto push.

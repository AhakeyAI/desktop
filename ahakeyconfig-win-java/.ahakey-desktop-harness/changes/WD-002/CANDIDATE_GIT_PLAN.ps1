# REVIEW before executing. This script stages ONLY listed paths and never commits.
# Stop other writers. Do not execute if the list includes private or unrelated material.
Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop'
$existing = @(git -c core.quotePath=false diff --cached --name-only)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Git index' }
if ($existing.Count -gt 0) { throw 'Index already contains staged changes. Review them separately; do not auto reset.' }
$paths = @(
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-002/CONTRACT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-002/EXECUTION_REPORT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-002/REFERENCES.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-002/REVIEW.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-002/builder_submission.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-002/guard-origin.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-002/preserved_foreign_inputs.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-002/review_pack.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-002/reviews/20261003T102347709569Z-c2970c/ACTUAL_DIFF.txt',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-002/reviews/20261003T102347709569Z-c2970c/FRESH_REVIEW_DLA_INDEPENDENT_20261003T1848.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-002/start-fingerprint.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/owner-alignment-WD-002-Q7-offline-edit-correction-20261003.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/owner-approval-WD-002-q7-route-repair-20261003.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/owner-confirmation-WD-002-contract-20261003.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/owner-preserve-foreign-WD-002-pom-20261003.md',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/app/StudioController.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/model/DeviceStatus.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/model/StudioState.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/protocol/AhaKeyProtocol.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/protocol/AhaKeyResponseParser.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/BleManager.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/CanvasPane.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/InspectorPane.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/TopBar.java',
    'ahakeyconfig-win-java/src/main/resources/messages_en.properties',
    'ahakeyconfig-win-java/src/main/resources/messages_zh.properties'
)
$checkPaths = @(
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/app/StudioController.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/model/DeviceStatus.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/model/StudioState.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/protocol/AhaKeyProtocol.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/protocol/AhaKeyResponseParser.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/BleManager.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/CanvasPane.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/InspectorPane.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/TopBar.java',
    'ahakeyconfig-win-java/src/main/resources/messages_en.properties',
    'ahakeyconfig-win-java/src/main/resources/messages_zh.properties'
)
git --literal-pathspecs add -- $paths
if ($LASTEXITCODE -ne 0) { throw 'git add failed; stop and inspect, do not force-add' }
if ($checkPaths.Count -gt 0) {
  git --literal-pathspecs diff --cached --check -- $checkPaths
  if ($LASTEXITCODE -ne 0) { throw 'Staged product whitespace/conflict checks failed' }
}
git --no-pager diff --cached --stat
# Inspect actual staged diff, then Owner explicitly runs (not executed here):
# git commit -m 'WD-002 candidate pending Owner UAT'
# Check $LASTEXITCODE immediately after any Owner-run git commit, before writing evidence.
# An empty staged diff may mean an existing candidate is already saved: inspect/reuse it,
# do not claim that a new commit was created. No empty or duplicate commit is required.
# Record 'created new commit' vs 'reused verified existing commit' truthfully, with full hash.
# Git hooks may run in a user commit. Recheck candidate afterwards; no auto push.

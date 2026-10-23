# REVIEW before executing. This script stages ONLY listed paths and never commits.
# Stop other writers. Do not execute if the list includes private or unrelated material.
Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop'
$existing = @(git -c core.quotePath=false diff --cached --name-only)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Git index' }
if ($existing.Count -gt 0) { throw 'Index already contains staged changes. Review them separately; do not auto reset.' }
$paths = @(
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-001/CONTRACT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-001/EXECUTION_REPORT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-001/REFERENCES.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-001/REVIEW.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-001/builder_submission.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-001/guard-origin.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-001/review_pack.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-001/reviews/20260929T015254974735Z-a25f6f/ACTUAL_DIFF.txt',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-001/start-fingerprint.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness\changes\WD-001\REVIEW.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness\evidence\owner-approval-WD-001.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness\evidence\owner-task-cp3a-sleep-wait-time.md',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/protocol/AhaKeyProtocol.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/protocol/AhaKeyResponseParser.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/BleManager.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/TopBar.java',
    'ahakeyconfig-win-java/src/main/resources/messages_en.properties',
    'ahakeyconfig-win-java/src/main/resources/messages_zh.properties'
)
git --literal-pathspecs add -- $paths
if ($LASTEXITCODE -ne 0) { throw 'git add failed; stop and inspect, do not force-add' }
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Staged whitespace/conflict checks failed' }
git --no-pager diff --cached --stat
# Inspect actual staged diff, then Owner explicitly runs (not executed here):
# git commit -m 'WD-001 candidate pending Owner UAT'
# Git hooks may run in a user commit. Recheck candidate afterwards; no auto push.

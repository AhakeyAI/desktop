# REVIEW before executing. This script stages ONLY listed paths and never commits.
# Stop other writers. Do not execute if the list includes private or unrelated material.
Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop'
$existing = @(git -c core.quotePath=false diff --cached --name-only)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Git index' }
if ($existing.Count -gt 0) { throw 'Index already contains staged changes. Review them separately; do not auto reset.' }
$paths = @(
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/ACCEPTANCE.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/AUTO_CAPABILITY_UI_CONTRACT_R5_20261021.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/CONTRACT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/CROSS_COMPONENT_WORK_20261018.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/DECISIONS.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/DESIGN_REVIEW.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/EXECUTION_REPORT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/FORMAL_REVIEW_R9_20261021.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/IMPLEMENTATION_RECEIPT.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/IMPLEMENTATION_SCOPE.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/PREVIEW_FIX_CONTRACT_R3_20261018.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/PROTOCOL_AND_STATE.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/R6_ISOLATION_INTERFACE_PROPOSAL_20261020.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/REFERENCES.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/REGISTRATION.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/REVIEW.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builder_submission.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/foreign_acceptance.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/guard-origin.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/preserved_foreign_inputs.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/review_pack.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/reviews/20261021T023808688339Z-41baa7/ACTUAL_DIFF.txt',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/reviews/20261021T023808688339Z-41baa7/FRESH_ACTUAL_REVIEW_R9_20261021_661dbf42.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/start-fingerprint.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/20261015-wd005-owner-scope-approval.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/20261021-wd005-capability-ui-owner-authorization.md',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/app/StudioController.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/model/DeviceStatus.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/model/DisplayConfigState.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/protocol/AhaKeyProtocol.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/AiRuntimeDisplayService.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/BleManager.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/DisplayConfigService.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/view/InspectorPane.java',
    'ahakeyconfig-win-java/src/main/resources/messages_en.properties',
    'ahakeyconfig-win-java/src/main/resources/messages_zh.properties',
    'ahakeyconfig-win-java/src/main/resources/style.css',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/displayconfig/DisplayConfigCapabilityChecks.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/displayconfig/DisplayConfigChecks.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/displayconfig/DisplayConfigIsolationChecks.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/displayconfig/DisplayConfigRaceChecks.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/displayconfig/DisplayConfigRevision3Checks.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/displayconfig/DisplayConfigRound5Checks.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/displayconfig/OfflineBleManager.java'
)
git --literal-pathspecs add -- $paths
if ($LASTEXITCODE -ne 0) { throw 'git add failed; stop and inspect, do not force-add' }
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Staged whitespace/conflict checks failed' }
git --no-pager diff --cached --stat
# Inspect actual staged diff, then Owner explicitly runs (not executed here):
# git commit -m 'WD-005 candidate pending Owner UAT'
# Check $LASTEXITCODE immediately after any Owner-run git commit, before writing evidence.
# An empty staged diff may mean an existing candidate is already saved: inspect/reuse it,
# do not claim that a new commit was created. No empty or duplicate commit is required.
# Record 'created new commit' vs 'reused verified existing commit' truthfully, with full hash.
# Git hooks may run in a user commit. Recheck candidate afterwards; no auto push.

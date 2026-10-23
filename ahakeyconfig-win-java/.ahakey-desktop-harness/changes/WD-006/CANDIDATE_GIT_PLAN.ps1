# REVIEW before executing. This script stages ONLY listed paths and never commits.
# Stop other writers. Do not execute if the list includes private or unrelated material.
Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop'
$existing = @(git -c core.quotePath=false diff --cached --name-only)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Git index' }
if ($existing.Count -gt 0) { throw 'Index already contains staged changes. Review them separately; do not auto reset.' }
$paths = @(
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-006/CONTRACT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-006/EXECUTION_REPORT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-006/FRESH_REVIEW_BINDING_20261023.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-006/IMPLEMENTATION_RECEIPT.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-006/REFERENCES.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-006/REVIEW.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-006/SOURCE_MANIFEST.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-006/builder_submission.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-006/guard-origin.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-006/preserved_foreign_inputs.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-006/review_pack.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-006/reviews/20261023T034817004540Z-6b2f2d/ACTUAL_DIFF.txt',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-006/start-fingerprint.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/20261023-wd006-main-model-owner-approval.md',
    'ahakeyconfig-win-java/pom.xml',
    'ahakeyconfig-win-java/scripts/package-local-model.ps1',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/App.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/config/ModelConfig.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/SpeechService.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/service/VoiceInputManager.java',
    'ahakeyconfig-win-java/src/main/java/com/example/ahakey/sherpa/LibraryLoader.java',
    'ahakeyconfig-win-java/src/main/resources/model_config.properties',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/speech/SpeechLifecycleCheck.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/speech/SpeechNativeCheck.java',
    'ahakeyconfig-win-java/src/test/java/com/example/ahakey/speech/SpeechNativeFailureCheck.java',
    'ahakeyconfig-win-java/third-party/sherpa-onnx-java-api-1.13.3.jar'
)
git --literal-pathspecs add -- $paths
if ($LASTEXITCODE -ne 0) { throw 'git add failed; stop and inspect, do not force-add' }
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Staged whitespace/conflict checks failed' }
git --no-pager diff --cached --stat
# Inspect actual staged diff, then Owner explicitly runs (not executed here):
# git commit -m 'WD-006 candidate pending Owner UAT'
# Check $LASTEXITCODE immediately after any Owner-run git commit, before writing evidence.
# An empty staged diff may mean an existing candidate is already saved: inspect/reuse it,
# do not claim that a new commit was created. No empty or duplicate commit is required.
# Record 'created new commit' vs 'reused verified existing commit' truthfully, with full hash.
# Git hooks may run in a user commit. Recheck candidate afterwards; no auto push.

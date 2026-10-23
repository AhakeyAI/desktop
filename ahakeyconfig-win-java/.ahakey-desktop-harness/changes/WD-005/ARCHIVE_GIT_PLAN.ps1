# REVIEW before executing. This script stages ONLY listed paths and never commits.
# Stop other writers. Do not execute if the list includes private or unrelated material.
Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop'
$existing = @(git -c core.quotePath=false diff --cached --name-only)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Git index' }
if ($existing.Count -gt 0) { throw 'Index already contains staged changes. Review them separately; do not auto reset.' }
$paths = @(
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/ACCEPTANCE.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/ACCEPTANCE_COVERAGE.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/ARCHIVE_BUILD_EVIDENCE_20261022.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/AUTO_CAPABILITY_UI_CONTRACT_R5_20261021.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/BUILD_RECEIPT.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/CONTRACT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/CROSS_COMPONENT_WORK_20261018.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/DECISIONS.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/DEFERRED_FOLLOWUPS_20261022.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/DELIVERY_EVIDENCE_GAP_AUDIT_20261022.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/DELIVERY_PACKET.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/DELIVERY_PROFILE.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/DESIGN_REVIEW.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/EXECUTION_REPORT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/FORMAL_ARTIFACT_DLA_VERIFICATION_20261022.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/FORMAL_BUILD_HANDOFF_20261022.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/FORMAL_FIRMWARE_GATE.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/FORMAL_REVIEW_R9_20261021.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/IMPLEMENTATION_CHECKS_ROUND_9_20261021.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/IMPLEMENTATION_RECEIPT.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/IMPLEMENTATION_SCOPE.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/OWNER_BRIEF.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/OWNER_BRIEF_INPUT.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/OWNER_RESULTS.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/OWNER_TEST.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/OWNER_TEST.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/PREVIEW_FIX_CONTRACT_R3_20261018.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/PROTOCOL_AND_STATE.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/R6_ISOLATION_INTERFACE_PROPOSAL_20261020.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/REFERENCES.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/REGISTRATION.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/REVIEW.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/archive-evidence/20261022-formal-build-logs/java-identity.stderr.log.txt',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/archive-evidence/20261022-formal-build-logs/maven-identity.stdout.log.txt',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/archive-evidence/20261022-formal-build-logs/package.stdout.log.txt',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builder_submission.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/ARTIFACT_MANIFEST.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/BUILD_DETAILS.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/BUILD_EXECUTION.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/BUILD_REPORT.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/CANVAS_SOURCE_COMPARISON.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/CanvasPane.current.javap.txt',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/CanvasPane.current.utf8.javap.txt',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/CanvasPane.preview.javap.txt',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/CanvasPane.preview.utf8.javap.txt',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/FINGERPRINT_AFTER.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/FINGERPRINT_BEFORE.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/JAVAP_DIFFERENCES.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/JAVAP_EXECUTION.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/LOG_MANIFEST.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/PREVIEW_COMPARISON.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/PREVIEW_DIFFERENCE_ANALYSIS.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/RECEIPT.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/START.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/builds/20261022T004444327311Z-731fe2/STATIC_INSPECTION.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/candidate.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/foreign_acceptance.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/guard-origin.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/preserved_foreign_inputs.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/review_pack.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/reviews/20261021T023808688339Z-41baa7/ACTUAL_DIFF.txt',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/reviews/20261021T023808688339Z-41baa7/FRESH_ACTUAL_REVIEW_R9_20261021_661dbf42.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/start-fingerprint.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/test_packet.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/changes/WD-005/verification.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/20261015-wd005-owner-scope-approval.json',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/20261021-wd005-capability-ui-owner-authorization.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/20261022-wd005-formal-build-only-owner-authorization.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/evidence/20261022-wd005-limited-closeout-owner-decision.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/previews/WD-005/preview-20261021T024920511394Z-2ae03d/DLA_HANDOFF_VERIFICATION_20261021.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/previews/WD-005/preview-20261021T024920511394Z-2ae03d/OWNER_PASS_FEEDBACK_20261021.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/previews/WD-005/preview-20261021T024920511394Z-2ae03d/OWNER_PREVIEW_BRIEF_20261021.md',
    'ahakeyconfig-win-java/.ahakey-desktop-harness/previews/WD-005/preview-20261021T024920511394Z-2ae03d/PREVIEW_RECEIPT.json'
)
git --literal-pathspecs add -- $paths
if ($LASTEXITCODE -ne 0) { throw 'git add failed; stop and inspect, do not force-add' }
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Staged whitespace/conflict checks failed' }
git --no-pager diff --cached --stat
# Inspect actual staged diff, then Owner explicitly runs (not executed here):
# git commit -m 'WD-005 archive verified internal integration'
# Check $LASTEXITCODE immediately after any Owner-run git commit, before writing evidence.
# An empty staged diff may mean an existing candidate is already saved: inspect/reuse it,
# do not claim that a new commit was created. No empty or duplicate commit is required.
# Record 'created new commit' vs 'reused verified existing commit' truthfully, with full hash.
# Git hooks may run in a user commit. Recheck candidate afterwards; no auto push.

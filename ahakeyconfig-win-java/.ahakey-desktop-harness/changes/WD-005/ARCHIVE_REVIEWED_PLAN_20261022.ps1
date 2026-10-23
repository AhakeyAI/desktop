# DLA-reviewed exact WD-005 result record list. Requires separate Owner Git authorization.
# Stages only 74 named records. Does not commit or push.
$ErrorActionPreference = 'Stop'
$workspace = 'C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java'
$repo = Split-Path -Parent $workspace
$manifestPath = Join-Path $workspace '.ahakey-desktop-harness/changes/WD-005/ARCHIVE_REVIEWED_INPUTS_20261022.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Set-Location -LiteralPath $repo
$head = git rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $head.Trim() -ne $manifest.expected_head) { throw 'HEAD changed; stop for review' }
$existing = @(git diff --cached --name-only)
if ($LASTEXITCODE -ne 0 -or $existing.Count -ne 0) { throw 'Index not empty or unavailable; do not reset' }
$official = Join-Path $workspace $manifest.official_plan.path
if ((Get-FileHash -LiteralPath $official -Algorithm SHA256).Hash.ToLower() -ne $manifest.official_plan.sha256) { throw 'Official plan changed' }
$entries = @($manifest.files.PSObject.Properties)
if ($entries.Count -ne 74) { throw 'Exact list count changed' }
$paths = @()
foreach ($entry in $entries) {
    $absolute = Join-Path $workspace $entry.Name
    if ((Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToLower() -ne $entry.Value) { throw ('Record changed: ' + $entry.Name) }
    $paths += 'ahakeyconfig-win-java/' + $entry.Name
}
git --literal-pathspecs add -- $paths
if ($LASTEXITCODE -ne 0) { throw 'Staging failed; inspect without reset or force-add' }
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Staged diff check failed; do not commit' }
$staged = @(git -c core.quotePath=false diff --cached --name-only)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect staged paths' }
foreach ($p in $staged) { if ($paths -cnotcontains $p) { throw ('Unexpected staged path: ' + $p) } }
git --no-pager diff --cached --stat
# Inspect actual staged diff before separately authorized commit.
# Suggested message: WD-005 archive limited Windows USB acceptance
# No push, no source change, no device operation.

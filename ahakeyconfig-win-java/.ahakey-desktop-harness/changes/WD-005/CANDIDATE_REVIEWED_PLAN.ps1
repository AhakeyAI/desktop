# DLA-reviewed supplement to the generated 44-path plan. Never commits.
# Read this file and CANDIDATE_REVIEWED_INPUTS.json before execution.
$ErrorActionPreference = 'Stop'
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'CANDIDATE_REVIEWED_INPUTS.json') | ConvertFrom-Json
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
Set-Location -LiteralPath (Split-Path -Parent $projectRoot)
$head = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $manifest.expected_head) { throw 'HEAD changed; return to DLA before staging.' }
$existing = @(git -c core.quotePath=false diff --cached --name-only)
if ($LASTEXITCODE -ne 0 -or $existing.Count -gt 0) { throw 'Git index unavailable or nonempty; do not reset it.' }
$paths = @()
foreach ($item in $manifest.files) {
    $path = [string]$item.path
    if (-not $path.StartsWith('ahakeyconfig-win-java/') -or $path.Contains('..') -or $path.Contains(':')) { throw 'Unexpected path; stop.' }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $item.sha256) { throw ('Input changed: ' + $path) }
    $paths += $path
}
git --literal-pathspecs add -- $paths
if ($LASTEXITCODE -ne 0) { throw 'Staging failed; stop. No force-add or automatic cleanup.' }
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Staged diff check failed; return output to DLA.' }
git --no-pager diff --cached --stat
# Review actual staged diff with: git --no-pager diff --cached
# Only after Owner inspection:
# git commit -m "WD-005 R9 candidate pending formal UAT"
# Check exit code immediately, then git rev-parse HEAD. Never push automatically.

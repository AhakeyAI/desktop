param(
    [string]$PrivateInputDir = (Join-Path $PSScriptRoot "release-private"),
    [Parameter(Mandatory = $true)]
    [string]$FirmwareHex
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$requiredEnvironment = @(
    "TENCENTCLOUD_SECRET_ID",
    "TENCENTCLOUD_SECRET_KEY",
    "WECHAT_CLOUD_ENV_ID"
)
foreach ($name in $requiredEnvironment) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing environment variable: $name"
    }
}

$baseline = Join-Path $PrivateInputDir "AhaKeyStudio-voice-baseline.zip"
$wchIsp = Join-Path $PrivateInputDir "WCHISPTool-CH57x-59x.zip"
foreach ($path in @($baseline, $wchIsp, $FirmwareHex)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Release input is missing: $path"
    }
}

$expected = @{
    $baseline = "3202419edf0b137b73e39d5a97465385708e3100e6e49134c9809827783105df"
    $wchIsp = "e3949c1ee4c8c434ae2374c3d3b0ecf06a58ad2fd7eade20a83d2bec422eff36"
    $FirmwareHex = "10ff6af2e7b6915751794ca45d8dc8d8873a1c350d9c551436e6098876ff9a50"
}
foreach ($entry in $expected.GetEnumerator()) {
    $actual = (Get-FileHash -LiteralPath $entry.Key -Algorithm SHA256).
        Hash.ToLowerInvariant()
    if ($actual -ne $entry.Value) {
        throw "Release input SHA-256 mismatch: $($entry.Key)"
    }
}

$tcb = Get-Command tcb -ErrorAction SilentlyContinue
if (-not $tcb) {
    throw "CloudBase CLI is required. Install it with: npm install -g @cloudbase/cli@3"
}

& $tcb.Source login `
    --apiKeyId $env:TENCENTCLOUD_SECRET_ID `
    --apiKey $env:TENCENTCLOUD_SECRET_KEY
if ($LASTEXITCODE -ne 0) {
    throw "CloudBase authentication failed"
}

& $tcb.Source -e $env:WECHAT_CLOUD_ENV_ID storage upload $baseline `
    "release-inputs/AhaKeyStudio-voice-baseline.zip"
if ($LASTEXITCODE -ne 0) { throw "Baseline upload failed" }
& $tcb.Source -e $env:WECHAT_CLOUD_ENV_ID storage upload $wchIsp `
    "release-inputs/WCHISPTool-CH57x-59x.zip"
if ($LASTEXITCODE -ne 0) { throw "WCHISP upload failed" }
& $tcb.Source -e $env:WECHAT_CLOUD_ENV_ID storage upload $FirmwareHex `
    "release-inputs/AhaKey-X1-firmware-1.1.1-ch582.hex"
if ($LASTEXITCODE -ne 0) { throw "Firmware upload failed" }

Write-Output "RELEASE_INPUT_UPLOAD=OK"

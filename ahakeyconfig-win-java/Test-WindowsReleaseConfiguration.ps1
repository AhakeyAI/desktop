param(
    [string]$ProjectDir = $PSScriptRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$formalScripts = @(
    "build-installer.ps1",
    "build-release-installer.ps1",
    "build-exe.ps1"
)
foreach ($name in $formalScripts) {
    $path = Join-Path $ProjectDir $name
    $text = Get-Content -LiteralPath $path -Raw
    if ($text -match "(?m)^\s*&.*preview-part3-release-overlay\.ps1") {
        throw "$name must not invoke the legacy preview overlay."
    }
}

$overlay = Get-Content -LiteralPath (Join-Path $ProjectDir "preview-part3-release-overlay.ps1") -Raw
foreach ($marker in @("LEGACY", "NON-RELEASE", "UNSUPPORTED FOR CURRENT PRODUCTION BUILDS")) {
    if ($overlay -notmatch [regex]::Escape($marker)) {
        throw "Legacy overlay marker is missing: $marker"
    }
}

$artifactTest = Get-Content -LiteralPath (Join-Path $ProjectDir "Test-ReleaseArtifactContents.ps1") -Raw
foreach ($entry in @(
    "com/example/ahakey/service/AhaTypeConfig.class",
    "com/example/ahakey/service/AhaTypeService.class",
    "com/example/ahakey/service/CloudAccountManager.class",
    "com/example/ahakey/view/CloudAccountDialog.class",
    "com/example/ahakey/service/VoiceInputManager.class"
)) {
    if ($artifactTest -notmatch [regex]::Escape($entry)) {
        throw "Release artifact gate is missing: $entry"
    }
}

$wix = Get-Content -LiteralPath (Join-Path $ProjectDir "packaging\windows\main.wxs") -Raw
foreach ($marker in @(
    "8842DBEF-62F7-49AC-AF0F-9447198265F3",
    "03E5A934-FFCA-3815-B455-7D49BF1CA1DC",
    "AHAKEY_LEGACY_UPGRADE_FOUND",
    "RemoveExistingProducts",
    "AhaKeyStudio"
)) {
    if ($wix -notmatch [regex]::Escape($marker)) {
        throw "WiX upgrade/layout marker is missing: $marker"
    }
}

Write-Output "WINDOWS_RELEASE_CONFIGURATION=OK"

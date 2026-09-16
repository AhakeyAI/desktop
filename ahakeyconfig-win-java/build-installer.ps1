param(
    [string]$FirmwareHex = "",
    [string]$BaselineInstallDir = (Join-Path $env:ProgramFiles "AhaKeyStudio"),
    [string]$AppVersion = "",
    [string]$FirmwareVersion = "",
    [string]$WchIspBundleDir = "",
    [string]$WixBin = "",
    [Alias("IncludeWchIsp")]
    [switch]$IncludeLicensedWchIsp,
    [switch]$InternalValidationOnly,
    [switch]$PrepareOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($FirmwareVersion)) {
    if (-not $PrepareOnly -and -not $InternalValidationOnly) {
        throw "Formal installer builds require an explicit -FirmwareVersion."
    }
    $capabilitiesPath = Join-Path $PSScriptRoot `
        "src\main\resources\firmware-capabilities.properties"
    $capabilities = ConvertFrom-StringData `
        (Get-Content -LiteralPath $capabilitiesPath -Raw)
    $FirmwareVersion = [string]$capabilities.expectedBundledVersion
}

# Compatibility entry point. All installer builds use the protected release
# baseline so VoiceInputManager, ModelConfig and deployed ONNX resources cannot
# be replaced by development classes. SpeechService is intentionally overlaid
# for deterministic tensor cleanup.
& (Join-Path $PSScriptRoot "build-release-installer.ps1") `
    -BaselineInstallDir $BaselineInstallDir `
    -FirmwareHex $FirmwareHex `
    -AppVersion $AppVersion `
    -FirmwareVersion $FirmwareVersion `
    -WchIspBundleDir $WchIspBundleDir `
    -WixBin $WixBin `
    -IncludeLicensedWchIsp:$IncludeLicensedWchIsp `
    -InternalValidationOnly:$InternalValidationOnly `
    -PrepareOnly:$PrepareOnly
exit $LASTEXITCODE

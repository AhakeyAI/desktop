param(
    [Parameter(Mandatory = $true)]
    [string]$FirmwareHex,
    [string]$BaselineInstallDir = (Join-Path $env:ProgramFiles "AhaKeyStudio"),
    [string]$AppVersion = "",
    [string]$FirmwareVersion = "1.4.0",
    [string]$WchIspBundleDir = "",
    [string]$WixBin = "",
    [switch]$IncludeLicensedWchIsp,
    [switch]$PrepareOnly
)

# Compatibility entry point. All installer builds use the protected release
# baseline so the original VoiceInputManager, SpeechService, ModelConfig and
# deployed ONNX resources cannot be replaced by development classes.
& (Join-Path $PSScriptRoot "build-release-installer.ps1") `
    -BaselineInstallDir $BaselineInstallDir `
    -FirmwareHex $FirmwareHex `
    -AppVersion $AppVersion `
    -FirmwareVersion $FirmwareVersion `
    -WchIspBundleDir $WchIspBundleDir `
    -WixBin $WixBin `
    -IncludeLicensedWchIsp:$IncludeLicensedWchIsp `
    -PrepareOnly:$PrepareOnly
exit $LASTEXITCODE

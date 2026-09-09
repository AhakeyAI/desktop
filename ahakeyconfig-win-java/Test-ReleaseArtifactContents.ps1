param(
    [Parameter(Mandatory = $true)]
    [string]$JarPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$resolvedJar = [IO.Path]::GetFullPath($JarPath)
if (-not (Test-Path -LiteralPath $resolvedJar -PathType Leaf)) {
    throw "Release JAR does not exist: $resolvedJar"
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$requiredEntries = @(
    "com/example/ahakey/protocol/AhaKeyProtocol.class",
    "com/example/ahakey/protocol/AhaKeyResponseParser.class",
    "com/example/ahakey/app/WorkModeSynchronizer.class",
    "com/example/ahakey/app/ManualApprovalGate.class",
    "com/example/ahakey/service/ApprovalService.class",
    "com/example/ahakey/service/ApprovalSnapshot.class",
    "com/example/ahakey/service/ApprovalState.class",
    "com/example/ahakey/service/PhysicalStatusFreshness.class",
    "com/example/ahakey/service/BleManager.class",
    "com/example/ahakey/service/KimiAhaKeyBridge.class",
    "com/example/ahakey/service/UsbHidTransport.class",
    "com/example/ahakey/service/GifUploadRules.class",
    "com/example/ahakey/service/LightOperationCoordinator.class",
    "com/example/ahakey/service/BleBridgeProcessOwner.class",
    "com/example/ahakey/service/ScreenAnimationAssetStore.class",
    "com/example/ahakey/service/BleDriverLocator.class",
    "com/example/ahakey/app/ApplicationLifecycle.class",
    "com/example/ahakey/SingleInstanceChecker.class",
    "com/example/ahakey/firmware/IntelHexValidator.class",
    "com/example/ahakey/firmware/FirmwareUpdateService.class",
    "com/example/ahakey/firmware/FirmwareUpdateState.class",
    "com/example/ahakey/firmware/FirmwareUpdateError.class",
    "com/example/ahakey/firmware/FirmwareOperationHandle.class",
    "com/example/ahakey/firmware/FirmwareUpdateRequest.class",
    "com/example/ahakey/firmware/FirmwareUpdateResult.class",
    "com/example/ahakey/firmware/FirmwareUpdateStatus.class",
    "com/example/ahakey/firmware/RuntimeBundle.class",
    "com/example/ahakey/firmware/RuntimeIdentity.class",
    "com/example/ahakey/firmware/RuntimeProvider.class",
    "com/example/ahakey/firmware/WchIspRuntimeProvider.class",
    "com/example/ahakey/firmware/WchIspWorkspace.class",
    "com/example/ahakey/firmware/WchIspRunner.class",
    "com/example/ahakey/firmware/WchIspResultParser.class",
    "com/example/ahakey/firmware/IspDeviceProbe.class",
    "com/example/ahakey/firmware/ChipMatched.class",
    "com/example/ahakey/firmware/FirmwareUpdateDiagnostics.class",
    "com/example/ahakey/firmware/FirmwarePostVerifier.class",
    "com/example/ahakey/firmware/WchIspConfigLayout.class",
    "com/example/ahakey/firmware/OfficialWchIspAdapter.class",
    "com/example/ahakey/firmware/DefaultOfficialWchIspAdapter.class",
    "com/example/ahakey/firmware/PreparedFlashSession.class",
    "com/example/ahakey/firmware/PreparedLaunchContext.class",
    "com/example/ahakey/firmware/PreparationGeneration.class",
    "com/example/ahakey/firmware/RuntimeLocator.class",
    "com/example/ahakey/firmware/InstalledRuntimeLocator.class",
    "com/example/ahakey/firmware/WchIspRuntimeContract.class",
    "com/example/ahakey/update/WindowsUpdateInstaller.class",
    "com/example/ahakey/platform/windows/VoiceKeyPressState.class",
    "com/example/ahakey/platform/voice/VoiceAction.class",
    "com/example/ahakey/platform/voice/VoiceActionRouter.class",
    "com/example/ahakey/platform/voice/VoiceButtonEvent.class",
    "com/example/ahakey/platform/voice/VoiceButtonStateMachine.class",
    "firmware-capabilities.properties",
    "wchisp/CONFIG_CH57X59X-3.6.1-sanitized.WCH",
    "wchisp/baseline.properties",
    "wchisp/wchisp-runtime.json"
)

$archive = [IO.Compression.ZipFile]::OpenRead($resolvedJar)
try {
    $missing = @($requiredEntries | Where-Object { $null -eq $archive.GetEntry($_) })
    if ($missing.Count -gt 0) {
        throw "Release JAR is missing required P0 entries: $($missing -join ', ')"
    }
} finally {
    $archive.Dispose()
}

Write-Output "RELEASE_ARTIFACT_CONTENTS=OK"
Write-Output "JAR=$resolvedJar"
$requiredEntries | ForEach-Object { Write-Output "  $_" }

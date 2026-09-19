param(
    [Parameter(Mandatory = $true)]
    [string]$JarPath,
    [string]$ReleaseInputDir = ""
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
    "com/example/ahakey/service/SpeechService.class",
    "com/example/ahakey/sherpa/LibraryLoader.class",
    "firmware-capabilities.properties",
    "model_config.properties",
    "messages_ru.properties",
    "legacy_ru.properties",
    "wchisp/CONFIG_CH57X59X-sanitized.WCH",
    "wchisp/baseline.properties",
    "wchisp/wchisp-runtime.json"
)

$archive = [IO.Compression.ZipFile]::OpenRead($resolvedJar)
try {
    $missing = @($requiredEntries | Where-Object { $null -eq $archive.GetEntry($_) })
    if ($missing.Count -gt 0) {
        throw "Release JAR is missing required P0 entries: $($missing -join ', ')"
    }
    $modelConfigEntry = $archive.GetEntry("model_config.properties")
    $modelConfigReader = New-Object System.IO.StreamReader($modelConfigEntry.Open())
    try { $modelConfigText = $modelConfigReader.ReadToEnd() }
    finally { $modelConfigReader.Dispose() }
    if ($modelConfigText -notmatch '(?m)^model\.enabled=true\s*$' -or
        $modelConfigText -notmatch '(?m)^model\.type=STREAMING_PARAFORMER\s*$' -or
        $modelConfigText -notmatch '(?m)^model\.path=models\s*$') {
        throw "Release JAR model_config.properties does not declare the Sherpa deployment contract."
    }
} finally {
    $archive.Dispose()
}

Write-Output "RELEASE_ARTIFACT_CONTENTS=OK"
Write-Output "JAR=$resolvedJar"
$requiredEntries | ForEach-Object { Write-Output "  $_" }

if (-not [string]::IsNullOrWhiteSpace($ReleaseInputDir)) {
    $resolvedInput = [IO.Path]::GetFullPath($ReleaseInputDir)
    if (-not (Test-Path -LiteralPath $resolvedInput -PathType Container)) {
        throw "Release input directory does not exist: $resolvedInput"
    }
    foreach ($modelName in @(
        "encoder.int8.onnx",
        "decoder.int8.onnx",
        "silero_vad.onnx",
        "tokens.txt"
    )) {
        $modelPath = Join-Path $resolvedInput "models\$modelName"
        if (-not (Test-Path -LiteralPath $modelPath -PathType Leaf) -or
            (Get-Item -LiteralPath $modelPath).Length -eq 0) {
            throw "Release input is missing Sherpa model resource: $modelPath"
        }
    }
    $nativeDir = Join-Path $resolvedInput "lib\sherpa-onnx\native\win-x64"
    foreach ($nativeName in @(
        "onnxruntime.dll",
        "onnxruntime_providers_shared.dll",
        "sherpa-onnx-jni.dll"
    )) {
        $nativePath = Join-Path $nativeDir $nativeName
        if (-not (Test-Path -LiteralPath $nativePath -PathType Leaf) -or
            (Get-Item -LiteralPath $nativePath).Length -eq 0) {
            throw "Release input is missing Sherpa native resource: $nativePath"
        }
    }
    $apiJar = Join-Path $resolvedInput "lib\sherpa-onnx-java-api-1.13.3.jar"
    if (-not (Test-Path -LiteralPath $apiJar -PathType Leaf) -or
        (Get-Item -LiteralPath $apiJar).Length -eq 0) {
        throw "Release input is missing Sherpa Java API: $apiJar"
    }
    Write-Output "SHERPA_RELEASE_INPUT=OK"
}

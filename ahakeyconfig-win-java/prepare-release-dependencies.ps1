param(
    [string]$BaselineInstallDir = (Join-Path $env:ProgramFiles "AhaKeyStudio"),
    [string]$WchIspBundleDir = "",
    [string]$OutputDir = (Join-Path $PSScriptRoot "release-private")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($WchIspBundleDir)) {
    throw "WchIspBundleDir must be supplied explicitly; no developer-machine fallback is allowed."
}
$WchIspBundleDir = [IO.Path]::GetFullPath($WchIspBundleDir)

$baselineApp = Join-Path $BaselineInstallDir "app"
$baselineRuntime = Join-Path $BaselineInstallDir "runtime"
$baselineResourceJar = Join-Path $baselineApp "ahakey-studio-1.0.0.jar"
$baselineIcon = Join-Path $BaselineInstallDir "AhaKeyStudio.ico"
$baselineModels = Join-Path $baselineApp "models"
$required = @(
    $baselineRuntime,
    $baselineIcon,
    (Join-Path $baselineModels "encoder.int8.onnx"),
    (Join-Path $baselineModels "decoder.int8.onnx"),
    (Join-Path $baselineModels "silero_vad.onnx"),
    (Join-Path $baselineModels "tokens.txt"),
    (Join-Path $WchIspBundleDir "WCHISPTool_CH57x-59x.exe"),
    (Join-Path $WchIspBundleDir "CH343PT.DLL"),
    (Join-Path $WchIspBundleDir "WCH55xISPDLL.dll"),
    (Join-Path $WchIspBundleDir "CONFIG_CH57X59X.WCH")
)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Release dependency is missing: $path"
    }
}
if (Test-Path -LiteralPath (Join-Path $baselineApp "models\model_q8.onnx")) {
    throw "Unsafe model_q8.onnx exists in the release baseline."
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputDir)
$resolvedProject = [IO.Path]::GetFullPath($PSScriptRoot)
if (-not $resolvedOutput.StartsWith(
    $resolvedProject, [StringComparison]::OrdinalIgnoreCase
)) {
    throw "OutputDir must stay inside the Windows project: $resolvedOutput"
}
New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null

$baselineZip = Join-Path $resolvedOutput "AhaKeyStudio-voice-baseline.zip"
$wchIspZip = Join-Path $resolvedOutput "WCHISPTool-CH57x-59x.zip"
$voiceStage = Join-Path $resolvedOutput "voice-baseline-stage"
$wchIspStage = Join-Path $resolvedOutput "wchisp-sanitized"
foreach ($archive in @($baselineZip, $wchIspZip)) {
    if (Test-Path -LiteralPath $archive) {
        Remove-Item -LiteralPath $archive -Force
    }
}
if (Test-Path -LiteralPath $wchIspStage) {
    Remove-Item -LiteralPath $wchIspStage -Recurse -Force
}
if (Test-Path -LiteralPath $voiceStage) {
    Remove-Item -LiteralPath $voiceStage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $voiceStage | Out-Null
New-Item -ItemType Directory -Force -Path $wchIspStage | Out-Null
foreach ($runtimeFile in @(
    "WCHISPTool_CH57x-59x.exe",
    "CH343PT.DLL",
    "WCH55xISPDLL.dll",
    "CONFIG_CH57X59X.WCH"
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $WchIspBundleDir $runtimeFile) -PathType Leaf)) {
        throw "WCHISP runtime bundle is missing: $runtimeFile"
    }
}
Get-ChildItem -LiteralPath $WchIspBundleDir -Force |
    Where-Object {
        $_.Name -notin @(
            "CONFIG_CH57X59X.WCH",
            "CONFIG_CH57X59X.WCH.excluded",
            "wchisp-runtime.json"
        )
    } |
    Copy-Item -Destination $wchIspStage -Recurse
[byte[]]$configBytes = [IO.File]::ReadAllBytes(
    (Join-Path $WchIspBundleDir "CONFIG_CH57X59X.WCH")
)
if ($configBytes.Length -ne 66841) {
    throw "Unsupported WCHISP configuration size: $($configBytes.Length)"
}
foreach ($offset in @(36486, 37006, 37526, 63172, 63692)) {
    if ($offset -lt 0 -or $offset + 520 -gt $configBytes.Length) {
        throw "WCHISP configuration path slot is outside the file: $offset"
    }
    [Array]::Clear($configBytes, $offset, 520)
}
$stagedConfig = Join-Path $wchIspStage "CONFIG_CH57X59X.WCH"
[IO.File]::WriteAllBytes($stagedConfig, $configBytes)

$stagedExe = Join-Path $wchIspStage "WCHISPTool_CH57x-59x.exe"
$stagedDriverDll = Join-Path $wchIspStage "CH343PT.DLL"
$stagedIspDll = Join-Path $wchIspStage "WCH55xISPDLL.dll"
$toolVersion = [string](Get-Item -LiteralPath $stagedExe).VersionInfo.FileVersion
$driverVersion = [string](Get-Item -LiteralPath $stagedDriverDll).VersionInfo.FileVersion
$ispVersion = [string](Get-Item -LiteralPath $stagedIspDll).VersionInfo.FileVersion
foreach ($versionEvidence in @($toolVersion, $driverVersion, $ispVersion)) {
    if ([string]::IsNullOrWhiteSpace($versionEvidence)) {
        throw "WCHISP runtime component lacks file-version evidence."
    }
}
$exeHash = (Get-FileHash -LiteralPath $stagedExe -Algorithm SHA256).Hash.ToLowerInvariant()
$driverHash = (Get-FileHash -LiteralPath $stagedDriverDll -Algorithm SHA256).Hash.ToLowerInvariant()
$ispHash = (Get-FileHash -LiteralPath $stagedIspDll -Algorithm SHA256).Hash.ToLowerInvariant()
$configHash = (Get-FileHash -LiteralPath $stagedConfig -Algorithm SHA256).Hash.ToLowerInvariant()
$runtimeMetadata = [ordered]@{
    bundleId = "wchisp-ch57x59x-packaged"
    toolVersion = $toolVersion.Trim()
    ispDllVersion = $ispVersion.Trim()
    driverDllVersion = $driverVersion.Trim()
    configContractVersion = "sanitized-five-path-slots-v1"
    configLayoutFingerprint = $configHash
    supportedChipFamily = "CH57x/CH59x"
    supportedModel = "CH582"
    source = "User-supplied official WCHISP bundle; redistribution authorization not verified"
    provenance = "Versions and file hashes recorded during packaging; persisted firmware paths removed"
    exeSha256 = $exeHash
    ch343Sha256 = $driverHash
    ispDllSha256 = $ispHash
    configSha256 = $configHash
}
[IO.File]::WriteAllText(
    (Join-Path $wchIspStage "wchisp-runtime.json"),
    ($runtimeMetadata | ConvertTo-Json),
    [Text.UTF8Encoding]::new($false)
)
& (Join-Path $PSScriptRoot "Test-WchIspReleasePrivacy.ps1") -RootPath $wchIspStage

# The private voice archive contains only non-Java release assets. In
# particular, the historical Java baseline JAR is never copied into staging.
Copy-Item -LiteralPath $baselineRuntime -Destination (Join-Path $voiceStage "runtime") -Recurse
New-Item -ItemType Directory -Force -Path (Join-Path $voiceStage "app\models") | Out-Null
Get-ChildItem -LiteralPath $baselineModels -Force |
    Copy-Item -Destination (Join-Path $voiceStage "app\models") -Recurse
Copy-Item -LiteralPath $baselineIcon -Destination (Join-Path $voiceStage "AhaKeyStudio.ico")

$nativeSource = Join-Path $baselineApp "lib\sherpa-onnx\native\win-x64"
$nativeStage = Join-Path $voiceStage "app\lib\sherpa-onnx\native\win-x64"
New-Item -ItemType Directory -Force -Path $nativeStage | Out-Null
if (Test-Path -LiteralPath $nativeSource -PathType Container) {
    foreach ($nativeName in @("onnxruntime.dll", "onnxruntime_providers_shared.dll", "sherpa-onnx-jni.dll")) {
        Copy-Item -LiteralPath (Join-Path $nativeSource $nativeName) -Destination $nativeStage
    }
} elseif (Test-Path -LiteralPath $baselineResourceJar -PathType Leaf) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($baselineResourceJar)
    try {
        foreach ($nativeName in @("onnxruntime.dll", "onnxruntime_providers_shared.dll", "sherpa-onnx-jni.dll")) {
            $entry = $archive.GetEntry("sherpa-onnx/native/win-x64/$nativeName")
            if ($null -eq $entry) { throw "Sherpa native resource is missing: $nativeName" }
            $outputPath = Join-Path $nativeStage $nativeName
            $input = $entry.Open()
            $output = [IO.File]::Create($outputPath)
            try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
        }
    } finally { $archive.Dispose() }
} else {
    throw "Authorized Sherpa native sidecar is missing and no resource-only extraction source is available."
}

Compress-Archive `
    -Path (Join-Path $voiceStage "*") `
    -DestinationPath $baselineZip `
    -CompressionLevel Optimal
Compress-Archive `
    -Path (Join-Path $wchIspStage "*") `
    -DestinationPath $wchIspZip `
    -CompressionLevel Optimal
Remove-Item -LiteralPath $wchIspStage -Recurse -Force
Remove-Item -LiteralPath $voiceStage -Recurse -Force

foreach ($archive in @($baselineZip, $wchIspZip)) {
    $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).
        Hash.ToLowerInvariant()
    $hashFile = "$archive.sha256"
    [IO.File]::WriteAllText(
        $hashFile,
        "$hash  $([IO.Path]::GetFileName($archive))`n",
        [Text.UTF8Encoding]::new($false)
    )
    Write-Output "$([IO.Path]::GetFileName($archive))=$hash"
}

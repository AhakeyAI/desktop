param(
    [string]$BaselineInstallDir = (Join-Path $env:ProgramFiles "AhaKeyStudio"),
    [string]$WchIspBundleDir = "C:\app\WCHISPTool\WCHISPTool_CH57x-59x",
    [string]$OutputDir = (Join-Path $PSScriptRoot "release-private")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$baselineApp = Join-Path $BaselineInstallDir "app"
$baselineRuntime = Join-Path $BaselineInstallDir "runtime"
$baselineJar = Join-Path $baselineApp "ahakey-studio-1.0.0.jar"
$required = @(
    $baselineJar,
    $baselineRuntime,
    (Join-Path $baselineApp "models\encoder.int8.onnx"),
    (Join-Path $baselineApp "models\decoder.int8.onnx"),
    (Join-Path $baselineApp "models\silero_vad.onnx"),
    (Join-Path $baselineApp "models\tokens.txt"),
    (Join-Path $WchIspBundleDir "WCHISPTool_CH57x-59x.exe")
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
$wchIspStage = Join-Path $resolvedOutput "wchisp-sanitized"
foreach ($archive in @($baselineZip, $wchIspZip)) {
    if (Test-Path -LiteralPath $archive) {
        Remove-Item -LiteralPath $archive -Force
    }
}
if (Test-Path -LiteralPath $wchIspStage) {
    Remove-Item -LiteralPath $wchIspStage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $wchIspStage | Out-Null
Get-ChildItem -LiteralPath $WchIspBundleDir -Force |
    Where-Object { $_.Name -ne "CONFIG_CH57X59X.WCH" } |
    Copy-Item -Destination $wchIspStage -Recurse

Compress-Archive `
    -LiteralPath $BaselineInstallDir `
    -DestinationPath $baselineZip `
    -CompressionLevel Optimal
Compress-Archive `
    -Path (Join-Path $wchIspStage "*") `
    -DestinationPath $wchIspZip `
    -CompressionLevel Optimal
Remove-Item -LiteralPath $wchIspStage -Recurse -Force

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

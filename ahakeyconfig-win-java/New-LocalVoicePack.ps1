<#
.SYNOPSIS
Builds the downloadable local voice pack and its manifest.json.

.DESCRIPTION
Local voice is an optional feature: the installer never bundles speech
models or Sherpa native DLLs. When a user turns local voice on, the client
downloads the files listed in https://ahakey.com/local-voice/manifest.json
and checks each file's size and SHA-256.

This script lays out the files the client expects, computes their sizes and
hashes, and writes manifest.json. Upload the whole output directory so that
"<BaseUrl>/<path>" serves each file and "<BaseUrl>/manifest.json" (or
https://ahakey.com/local-voice/manifest.json) serves the manifest.

.EXAMPLE
.\New-LocalVoicePack.ps1 -ModelDir C:\release\models `
  -NativeDir C:\release\sherpa-native\win-x64 `
  -PackId paraformer-zh-en-int8-1 `
  -BaseUrl https://ahakey.com/local-voice/paraformer-zh-en-int8-1 `
  -OutputDir C:\release\local-voice-pack
#>
param(
    [Parameter(Mandatory = $true)][string]$ModelDir,
    [Parameter(Mandatory = $true)][string]$NativeDir,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')][string]$PackId,
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$OutputDir
)

$ErrorActionPreference = "Stop"

if (-not $BaseUrl.StartsWith("https://")) {
    throw "BaseUrl must use https: $BaseUrl"
}
$BaseUrl = $BaseUrl.TrimEnd("/")

# Must match LocalVoiceManifest.REQUIRED_PATHS / OPTIONAL_PATHS in the client.
$entries = @(
    @{ Path = "models/encoder.int8.onnx"; Source = (Join-Path $ModelDir "encoder.int8.onnx"); Required = $true },
    @{ Path = "models/decoder.int8.onnx"; Source = (Join-Path $ModelDir "decoder.int8.onnx"); Required = $true },
    @{ Path = "models/tokens.txt"; Source = (Join-Path $ModelDir "tokens.txt"); Required = $true },
    @{ Path = "models/silero_vad.onnx"; Source = (Join-Path $ModelDir "silero_vad.onnx"); Required = $false },
    @{ Path = "native/win-x64/onnxruntime.dll"; Source = (Join-Path $NativeDir "onnxruntime.dll"); Required = $true },
    @{ Path = "native/win-x64/onnxruntime_providers_shared.dll"; Source = (Join-Path $NativeDir "onnxruntime_providers_shared.dll"); Required = $false },
    @{ Path = "native/win-x64/sherpa-onnx-jni.dll"; Source = (Join-Path $NativeDir "sherpa-onnx-jni.dll"); Required = $true }
)

if (Test-Path -LiteralPath (Join-Path $ModelDir "model_q8.onnx")) {
    Write-Warning "model_q8.onnx is not used by the client and is not included."
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$files = @()
foreach ($entry in $entries) {
    if (-not (Test-Path -LiteralPath $entry.Source -PathType Leaf)) {
        if ($entry.Required) { throw "Required local voice file is missing: $($entry.Source)" }
        continue
    }
    $item = Get-Item -LiteralPath $entry.Source
    if ($item.Length -le 0) { throw "Local voice file is empty: $($entry.Source)" }
    $destination = Join-Path $OutputDir ($entry.Path -replace "/", "\")
    New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
    Copy-Item -LiteralPath $entry.Source -Destination $destination -Force
    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    $files += [ordered]@{
        path   = $entry.Path
        url    = "$BaseUrl/$($entry.Path)"
        size   = $item.Length
        sha256 = $hash
    }
    Write-Output ("{0,-48} {1,12:N0} bytes  {2}" -f $entry.Path, $item.Length, $hash)
}

$manifest = [ordered]@{
    schema = 1
    packId = $PackId
    files  = $files
}
$manifestPath = Join-Path $OutputDir "manifest.json"
$json = $manifest | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText($manifestPath, $json, (New-Object Text.UTF8Encoding($false)))

$total = [long]0
foreach ($file in $files) { $total += [long]$file.size }
Write-Output ("LOCAL_VOICE_PACK=OK files={0} total={1:N0} bytes" -f $files.Count, $total)
Write-Output "MANIFEST=$manifestPath"

param(
    [Parameter(Mandatory = $true)]
    [string]$RootPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-ScanText {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        return @("", "")
    }
    $ascii = [Text.Encoding]::ASCII.GetString($Bytes)
    $be = if (($Bytes.Length % 2) -eq 0) {
        [Text.Encoding]::BigEndianUnicode.GetString($Bytes)
    } else {
        ""
    }
    return @($ascii, $be)
}

function Assert-WchIspReleasePrivacy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )
    $resolved = [IO.Path]::GetFullPath($RootPath)
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "WCHISP release root does not exist: $resolved"
    }
    foreach ($runtimeFile in @(
        "WCHISPTool_CH57x-59x.exe",
        "CH343PT.DLL",
        "WCH55xISPDLL.dll"
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $resolved $runtimeFile) -PathType Leaf)) {
            throw "WCHISP release is missing runtime component: $runtimeFile"
        }
    }
    $files = @(Get-ChildItem -LiteralPath $resolved -Recurse -File)
    $scanExtensions = @(
        ".wch", ".excluded", ".ini", ".txt", ".log", ".json", ".xml", ".zip"
    )
    $violations = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $files) {
        if ($scanExtensions -notcontains $file.Extension.ToLowerInvariant()) {
            continue
        }
        $payloads = @()
        if ($file.Extension -ieq ".zip") {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $archive = [IO.Compression.ZipFile]::OpenRead($file.FullName)
            try {
                foreach ($entry in $archive.Entries) {
                    if ($entry.FullName.EndsWith("/")) { continue }
                    $stream = $entry.Open()
                    try {
                        $memory = New-Object IO.MemoryStream
                        $stream.CopyTo($memory)
                        $payloads += ,@($entry.FullName, $memory.ToArray())
                    } finally {
                        $stream.Dispose()
                        if ($null -ne $memory) { $memory.Dispose() }
                    }
                }
            } finally { $archive.Dispose() }
        } else {
            $payloads += ,@($file.FullName, [IO.File]::ReadAllBytes($file.FullName))
        }
        foreach ($payload in $payloads) {
            $name = [string]$payload[0]
            $texts = Get-ScanText -Bytes ([byte[]]$payload[1])
            foreach ($text in $texts) {
                if ($text -match '(?i)([A-Z]:\\Users\\|[A-Z]:\\app\\|\\\\Users\\\\)') {
                    $violations.Add("developer absolute path in $($file.Name): $name")
                }
                if ($text -match '(?i)(?:old|history|previous|backup|developer)[^\r\n]{0,80}\.(?:hex|bin)') {
                    $violations.Add("historical firmware path in $($file.Name): $name")
                }
            }
        }
    }
    $config = Join-Path $resolved "CONFIG_CH57X59X.WCH"
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) {
        throw "WCHISP release is missing sanitized CONFIG_CH57X59X.WCH"
    }
    if (Test-Path -LiteralPath (Join-Path $resolved "CONFIG_CH57X59X.WCH.excluded")) {
        throw "WCHISP release contains forbidden CONFIG_CH57X59X.WCH.excluded"
    }
    $excludedFiles = @($files | Where-Object {
        $_.Name -ieq "CONFIG_CH57X59X.WCH.excluded"
    })
    if ($excludedFiles.Count -gt 0) {
        throw "WCHISP release contains forbidden excluded CONFIG files"
    }
    $configHash = (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($configHash -ne "4dd3ac5911ff428b92200745a26c34c674235c04ac40a77f7cfb61d6fb6241e8") {
        throw "WCHISP release CONFIG_CH57X59X.WCH is not the repository baseline"
    }
    $metadataPath = Join-Path $resolved "wchisp-runtime.json"
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw "WCHISP release is missing wchisp-runtime.json"
    }
    try {
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    } catch {
        throw "WCHISP runtime metadata is not valid JSON: $($_.Exception.Message)"
    }
    foreach ($property in @("toolVersion", "ispDllVersion", "driverDllVersion", "configContractVersion")) {
        if ([string]$metadata.$property -ne "3.6.1") {
            throw "WCHISP runtime contract mismatch: $property=$($metadata.$property)"
        }
    }
    if ([string]$metadata.configLayoutFingerprint -ne
        "4dd3ac5911ff428b92200745a26c34c674235c04ac40a77f7cfb61d6fb6241e8") {
        throw "WCHISP runtime config layout fingerprint mismatch"
    }
    if ([string]$metadata.supportedModel -ne "CH582" -or
        [string]$metadata.supportedChipFamily -ne "CH57x/CH59x") {
        throw "WCHISP runtime supported device contract mismatch"
    }
    if ($violations.Count -gt 0) {
        throw "WCHISP release privacy validation failed: $($violations -join '; ')"
    }
    Write-Output "WCHISP_RELEASE_PRIVACY=OK"
    Write-Output "WCHISP_RELEASE_PRIVACY_GATE=PASS"
}

if ($MyInvocation.InvocationName -ne '.') {
    Assert-WchIspReleasePrivacy -RootPath $RootPath
}

param(
    [Parameter(Mandatory = $true)]
    [string]$RootPath,
    [string]$WchIspBundleDir = ""
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
        [string]$RootPath,
        [string]$WchIspBundleDir = ""
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
    $chipDatabaseRelativePath = "ChipType\chiplist_CH57x_CH59x.wcfg"
    $chipDatabase = Join-Path $resolved $chipDatabaseRelativePath
    if (-not (Test-Path -LiteralPath $chipDatabase -PathType Leaf) -or
        (Get-Item -LiteralPath $chipDatabase).Length -eq 0) {
        throw "WCHISP release is missing chip database: $chipDatabaseRelativePath"
    }
    if (-not [string]::IsNullOrWhiteSpace($WchIspBundleDir)) {
        $sourceChipDatabase = Join-Path `
            ([IO.Path]::GetFullPath($WchIspBundleDir)) $chipDatabaseRelativePath
        if (-not (Test-Path -LiteralPath $sourceChipDatabase -PathType Leaf) -or
            (Get-Item -LiteralPath $sourceChipDatabase).Length -eq 0) {
            throw "Official WCHISP bundle is missing chip database: $chipDatabaseRelativePath"
        }
        [byte[]]$sourceChipDatabaseBytes = [IO.File]::ReadAllBytes($sourceChipDatabase)
        [byte[]]$stagedChipDatabaseBytes = [IO.File]::ReadAllBytes($chipDatabase)
        if ([Convert]::ToBase64String($sourceChipDatabaseBytes) -cne
            [Convert]::ToBase64String($stagedChipDatabaseBytes)) {
            throw "Staged WCHISP chip database differs from the official bundle source"
        }
    }
    $files = @(Get-ChildItem -LiteralPath $resolved -Recurse -File)
    $scanExtensions = @(
        ".wch", ".wcfg", ".excluded", ".ini", ".txt", ".log", ".json", ".xml", ".zip"
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
    [byte[]]$configBytes = [IO.File]::ReadAllBytes($config)
    if ($configBytes.Length -ne 66841) {
        throw "WCHISP CONFIG_CH57X59X.WCH has unsupported size: $($configBytes.Length)"
    }
    $repositoryConfig = Join-Path $PSScriptRoot `
        "src\main\resources\wchisp\CONFIG_CH57X59X-sanitized.WCH"
    if (-not (Test-Path -LiteralPath $repositoryConfig -PathType Leaf)) {
        throw "Verified repository WCHISP configuration is missing: $repositoryConfig"
    }
    [byte[]]$repositoryConfigBytes = [IO.File]::ReadAllBytes($repositoryConfig)
    if ([Convert]::ToBase64String($configBytes) -cne
        [Convert]::ToBase64String($repositoryConfigBytes)) {
        throw "Staged WCHISP CONFIG differs from the verified repository configuration"
    }
    foreach ($offset in @(36486, 37006, 37526, 63172, 63692)) {
        if ($offset -lt 0 -or $offset + 520 -gt $configBytes.Length) {
            throw "WCHISP CONFIG path slot is outside the file: $offset"
        }
        for ($index = $offset; $index -lt $offset + 520; $index++) {
            if ($configBytes[$index] -ne 0) {
                throw "WCHISP CONFIG contains a persisted firmware path at slot $offset"
            }
        }
    }
    $excludedFiles = @($files | Where-Object {
        $_.Name -ieq "CONFIG_CH57X59X.WCH.excluded"
    })
    if ($excludedFiles.Count -gt 0) {
        throw "WCHISP release contains forbidden excluded CONFIG files"
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
    foreach ($property in @(
        "bundleId",
        "toolVersion",
        "ispDllVersion",
        "driverDllVersion",
        "configContractVersion",
        "configLayoutFingerprint",
        "source",
        "provenance",
        "exeSha256",
        "ch343Sha256",
        "ispDllSha256",
        "configSha256"
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$metadata.$property)) {
            throw "WCHISP runtime metadata is missing: $property"
        }
    }
    $actualHashes = @{
        exeSha256 = (Get-FileHash -LiteralPath (Join-Path $resolved "WCHISPTool_CH57x-59x.exe") -Algorithm SHA256).Hash
        ch343Sha256 = (Get-FileHash -LiteralPath (Join-Path $resolved "CH343PT.DLL") -Algorithm SHA256).Hash
        ispDllSha256 = (Get-FileHash -LiteralPath (Join-Path $resolved "WCH55xISPDLL.dll") -Algorithm SHA256).Hash
        configSha256 = (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash
    }
    foreach ($property in $actualHashes.Keys) {
        if ([string]$metadata.$property -ne [string]$actualHashes[$property]) {
            throw "WCHISP runtime file hash mismatch: $property"
        }
    }
    if ([string]$metadata.configLayoutFingerprint -ne [string]$metadata.configSha256) {
        throw "WCHISP sanitized configuration fingerprint is inconsistent"
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
    Assert-WchIspReleasePrivacy `
        -RootPath $RootPath -WchIspBundleDir $WchIspBundleDir
}

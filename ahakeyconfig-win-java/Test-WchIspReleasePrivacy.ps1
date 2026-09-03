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
    if ($violations.Count -gt 0) {
        throw "WCHISP release privacy validation failed: $($violations -join '; ')"
    }
    Write-Output "WCHISP_RELEASE_PRIVACY=OK"
}

if ($MyInvocation.InvocationName -ne '.') {
    Assert-WchIspReleasePrivacy -RootPath $RootPath
}

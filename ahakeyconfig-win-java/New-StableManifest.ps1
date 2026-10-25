param(
    [Parameter(Mandatory = $true)]
    [string]$AppVersion,
    [Parameter(Mandatory = $true)]
    [string]$FirmwareVersion,
    [Parameter(Mandatory = $true)]
    [string]$Installer,
    [Parameter(Mandatory = $true)]
    [string]$FirmwareHex,
    [Parameter(Mandatory = $true)]
    [string]$PublicBaseUrl,
    [string]$NotesFile = "",
    [Parameter(Mandatory = $true)]
    [string]$Output
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

foreach ($pair in @{
    AppVersion = $AppVersion
    FirmwareVersion = $FirmwareVersion
}.GetEnumerator()) {
    if ($pair.Value -notmatch '^\d+\.\d+\.\d+$') {
        throw "$($pair.Key) must use MAJOR.MINOR.PATCH: $($pair.Value)"
    }
}
foreach ($path in @($Installer, $FirmwareHex)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Release asset is missing: $path"
    }
}

$expectedInstaller = "AhaKeyStudio-$AppVersion-windows-x64.exe"
$expectedFirmware = "AhaKey-X1-firmware-$FirmwareVersion-ch582.hex"
if ([IO.Path]::GetFileName($Installer) -ne $expectedInstaller) {
    throw "Installer must be named $expectedInstaller"
}
if ([IO.Path]::GetFileName($FirmwareHex) -ne $expectedFirmware) {
    throw "Firmware must be named $expectedFirmware"
}

$baseUri = [Uri]$PublicBaseUrl
if (-not $baseUri.IsAbsoluteUri -or $baseUri.Scheme -ne "https") {
    throw "PublicBaseUrl must be an absolute HTTPS URL"
}
$base = $PublicBaseUrl.TrimEnd("/")
$releasePath = "releases/v$AppVersion"
$notes = if (
    -not [string]::IsNullOrWhiteSpace($NotesFile) -and
    (Test-Path -LiteralPath $NotesFile -PathType Leaf)
) {
    (Get-Content -LiteralPath $NotesFile -Raw -Encoding UTF8).Trim()
} else {
    "AhaKey Studio $AppVersion stable release."
}

$manifest = [ordered]@{
    schemaVersion = 1
    channel = "stable"
    available = $true
    publishedAt = [DateTimeOffset]::UtcNow.ToString("o")
    app = [ordered]@{
        version = $AppVersion
        name = "AhaKey Studio $AppVersion"
        notes = $notes
        windows = [ordered]@{
            name = $expectedInstaller
            url = "$base/$releasePath/$expectedInstaller"
        }
    }
    firmware = [ordered]@{
        ch582 = [ordered]@{
            version = $FirmwareVersion
            name = $expectedFirmware
            url = "$base/$releasePath/$expectedFirmware"
        }
    }
}

$outputPath = [IO.Path]::GetFullPath($Output)
$outputParent = [IO.Path]::GetDirectoryName($outputPath)
if (-not [string]::IsNullOrWhiteSpace($outputParent)) {
    New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
}
[IO.File]::WriteAllText(
    $outputPath,
    ($manifest | ConvertTo-Json -Depth 8) + "`n",
    [Text.UTF8Encoding]::new($false)
)
Write-Output "STABLE_MANIFEST=$outputPath"

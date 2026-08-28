Set-StrictMode -Version Latest

function Get-AhaKeyFirmwareCapabilities {
    param([Parameter(Mandatory = $true)][string]$ProjectDir)
    $path = Join-Path $ProjectDir "src\main\resources\firmware-capabilities.properties"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Firmware capabilities file is missing: $path"
    }
    $values = ConvertFrom-StringData (Get-Content -LiteralPath $path -Raw)
    foreach ($name in @("minimumGifVersion", "minimumStabilizedFirmwareVersion", "expectedBundledVersion")) {
        if ([string]::IsNullOrWhiteSpace([string]$values[$name]) -or
            [string]$values[$name] -notmatch '^\d+\.\d+\.\d+$') {
            throw "Firmware capability $name is missing or invalid"
        }
    }
    foreach ($name in @("requiredProtocolVersion", "requiredCapabilityMask", "requiredDeviceModelName")) {
        if ([string]::IsNullOrWhiteSpace([string]$values[$name])) {
            throw "Firmware capability $name is missing or invalid"
        }
    }
    return $values
}

function Test-AhaKeyIntelHex {
    param([Parameter(Mandatory = $true)][string]$Path)
    $hasData = $false
    $hasEof = $false
    $lineNumber = 0
    foreach ($rawLine in [IO.File]::ReadLines([IO.Path]::GetFullPath($Path))) {
        $lineNumber++
        $line = $rawLine.Trim()
        if ($line.Length -eq 0) { continue }
        if ($hasEof) { throw "Intel HEX contains data after EOF at line $lineNumber" }
        if (-not $line.StartsWith(":") -or (($line.Length - 1) % 2) -ne 0) {
            throw "Intel HEX record format is invalid at line $lineNumber"
        }
        try {
            $record = for ($index = 1; $index -lt $line.Length; $index += 2) {
                [Convert]::ToByte($line.Substring($index, 2), 16)
            }
        } catch {
            throw "Intel HEX contains invalid hexadecimal data at line $lineNumber"
        }
        if ($record.Count -lt 5 -or $record.Count -ne ([int]$record[0] + 5)) {
            throw "Intel HEX byte count is invalid at line $lineNumber"
        }
        $sum = 0
        foreach ($value in $record) { $sum = ($sum + [int]$value) -band 0xFF }
        if ($sum -ne 0) { throw "Intel HEX checksum is invalid at line $lineNumber" }
        $type = [int]$record[3]
        if ($type -eq 0) { $hasData = $true }
        elseif ($type -eq 1) {
            if ([int]$record[0] -ne 0) { throw "Intel HEX EOF record is invalid" }
            $hasEof = $true
        } elseif ($type -gt 5) {
            throw "Intel HEX record type $type is unsupported"
        }
    }
    if (-not $hasData -or -not $hasEof) {
        throw "Intel HEX must contain non-empty data and an EOF record"
    }
}

function Assert-AhaKeyFirmwareReleaseInput {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectDir,
        [Parameter(Mandatory = $true)][string]$FirmwareVersion,
        [string]$FirmwareHex = "",
        [switch]$RequireFirmware
    )
    $capabilities = Get-AhaKeyFirmwareCapabilities -ProjectDir $ProjectDir
    $expectedVersion = [string]$capabilities.expectedBundledVersion
    if ($FirmwareVersion -cne $expectedVersion) {
        throw "FirmwareVersion must exactly match expectedBundledVersion $expectedVersion"
    }
    if ([string]::IsNullOrWhiteSpace($FirmwareHex)) {
        if ($RequireFirmware) { throw "A formal release requires -FirmwareHex" }
        return [pscustomobject]@{ Capabilities=$capabilities; FirmwareName=""; ProvenancePath="" }
    }
    if (-not (Test-Path -LiteralPath $FirmwareHex -PathType Leaf)) {
        throw "Firmware HEX does not exist: $FirmwareHex"
    }
    $expectedName = "AhaKey-X1-firmware-$expectedVersion-ch582.hex"
    if ([IO.Path]::GetFileName($FirmwareHex) -cne $expectedName) {
        throw "Firmware file must be named exactly $expectedName"
    }
    Test-AhaKeyIntelHex -Path $FirmwareHex
    $provenancePath = [IO.Path]::ChangeExtension([IO.Path]::GetFullPath($FirmwareHex), ".provenance.json")
    if (-not (Test-Path -LiteralPath $provenancePath -PathType Leaf)) {
        throw "Firmware provenance is missing: $provenancePath"
    }
    try { $provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json }
    catch { throw "Firmware provenance is invalid JSON: $provenancePath" }
    if ($provenance -is [System.Array] -or
        $provenance.PSObject.Properties.Name -cnotcontains "firmwareVersion" -or
        $provenance.firmwareVersion -isnot [string] -or
        $provenance.firmwareVersion -cne $expectedVersion) {
        throw "Firmware provenance firmwareVersion must exactly match $expectedVersion"
    }
    $requiredTextFields = @("deviceModel", "protocolVersion", "capabilityMask", "sourceCommit", "buildCommand", "builtAtUtc")
    foreach ($name in $requiredTextFields) {
        if ($provenance.PSObject.Properties.Name -cnotcontains $name -or
            $provenance.$name -isnot [string] -or
            [string]::IsNullOrWhiteSpace($provenance.$name)) {
            throw "Firmware provenance $name must be a non-empty string"
        }
    }
    if ($provenance.deviceModel -cne [string]$capabilities.requiredDeviceModelName) {
        throw "Firmware provenance deviceModel must exactly match $($capabilities.requiredDeviceModelName)"
    }
    if ($provenance.protocolVersion -cne [string]$capabilities.requiredProtocolVersion) {
        throw "Firmware provenance protocolVersion must exactly match $($capabilities.requiredProtocolVersion)"
    }
    if ($provenance.capabilityMask -cne [string]$capabilities.requiredCapabilityMask) {
        throw "Firmware provenance capabilityMask must exactly match $($capabilities.requiredCapabilityMask)"
    }
    if ($provenance.sourceCommit -cnotmatch '^[0-9a-f]{7,40}$') {
        throw "Firmware provenance sourceCommit must be a 7-40 character lowercase Git object id"
    }
    $builtAt = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParseExact(
        $provenance.builtAtUtc,
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$builtAt)) {
        throw "Firmware provenance builtAtUtc must use yyyy-MM-ddTHH:mm:ssZ"
    }
    return [pscustomobject]@{
        Capabilities=$capabilities
        FirmwareName=$expectedName
        ProvenancePath=$provenancePath
    }
}

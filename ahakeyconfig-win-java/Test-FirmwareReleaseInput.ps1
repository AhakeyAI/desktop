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
    if ([string]::IsNullOrWhiteSpace([string]$values.maxFirmwareAddress) -or
        [string]$values.maxFirmwareAddress -notmatch '^0x[0-9A-Fa-f]+$') {
        throw "Firmware capability maxFirmwareAddress is missing or invalid"
    }
    return $values
}

function Test-AhaKeyIntelHex {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][long]$MaxAddress
    )
    $hasData = $false
    $hasEof = $false
    $linearBase = [long]0
    $segmentBase = [long]0
    $ranges = @()
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
        $address = (([int]$record[1]) -shl 8) -bor [int]$record[2]
        if ($type -eq 0) {
            if ([int]$record[0] -le 0) {
                throw "Intel HEX data record must not be empty at line $lineNumber"
            }
            $hasData = $true
            $absolute = $linearBase + $segmentBase + $address
            $end = $absolute + [int]$record[0] - 1
            if ($absolute -lt 0 -or $end -lt $absolute -or $end -gt $MaxAddress) {
                throw "Intel HEX address exceeds the CH582 release range at line $lineNumber"
            }
            foreach ($range in $ranges) {
                if ($absolute -le $range[1] -and $end -ge $range[0]) {
                    throw "Intel HEX data records overlap at line $lineNumber"
                }
            }
            $ranges += ,@($absolute, $end)
        }
        elseif ($type -eq 1) {
            if ([int]$record[0] -ne 0) { throw "Intel HEX EOF record is invalid" }
            $hasEof = $true
        } elseif ($type -eq 2 -or $type -eq 4) {
            if ([int]$record[0] -ne 2) {
                throw "Intel HEX extended address record is invalid at line $lineNumber"
            }
            $upper = (([int]$record[4]) -shl 8) -bor [int]$record[5]
            if ($type -eq 2) {
                $segmentBase = ([long]$upper) -shl 4
                $linearBase = 0
            } else {
                $linearBase = ([long]$upper) -shl 16
                $segmentBase = 0
            }
        } elseif ($type -eq 3 -or $type -eq 5) {
            if ([int]$record[0] -ne 4) {
                throw "Intel HEX start address record is invalid at line $lineNumber"
            }
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
    $maxFirmwareAddress = [Convert]::ToInt64(
        ([string]$capabilities.maxFirmwareAddress).Substring(2), 16)
    Test-AhaKeyIntelHex -Path $FirmwareHex -MaxAddress $maxFirmwareAddress
    $provenancePath = [IO.Path]::ChangeExtension([IO.Path]::GetFullPath($FirmwareHex), ".provenance.json")
    if (-not (Test-Path -LiteralPath $provenancePath -PathType Leaf)) {
        throw "Firmware provenance is missing: $provenancePath"
    }
    $provenanceJson = Get-Content -LiteralPath $provenancePath -Raw
    try { $provenance = $provenanceJson | ConvertFrom-Json }
    catch { throw "Firmware provenance is invalid JSON: $provenancePath" }
    function Get-ProvenanceText([object]$object, [string]$name) {
        $property = $object.PSObject.Properties[$name]
        if ($null -eq $property -or $null -eq $property.Value) {
            throw "Firmware provenance $name must be a non-empty string"
        }
        if ($property.Value -is [System.Collections.IDictionary] -or
            ($property.Value -is [System.Collections.IEnumerable] -and
             $property.Value -isnot [string])) {
            throw "Firmware provenance $name must be a scalar value"
        }
        $text = [string]$property.Value
        if ([string]::IsNullOrWhiteSpace($text)) {
            throw "Firmware provenance $name must be a non-empty string"
        }
        return $text
    }
    $firmwareVersionText = Get-ProvenanceText $provenance "firmwareVersion"
    if ($provenance -is [System.Array] -or
        $firmwareVersionText -cne $expectedVersion) {
        throw "Firmware provenance firmwareVersion must exactly match $expectedVersion"
    }
    $requiredTextFields = @("deviceModel", "protocolVersion", "capabilityMask", "sourceCommit", "buildCommand", "builtAtUtc")
    $provenanceText = @{}
    foreach ($name in $requiredTextFields) {
        $provenanceText[$name] = Get-ProvenanceText $provenance $name
    }
    if ($provenanceText.deviceModel -cne [string]$capabilities.requiredDeviceModelName) {
        throw "Firmware provenance deviceModel must exactly match $($capabilities.requiredDeviceModelName)"
    }
    if ($provenanceText.protocolVersion -cne [string]$capabilities.requiredProtocolVersion) {
        throw "Firmware provenance protocolVersion must exactly match $($capabilities.requiredProtocolVersion)"
    }
    if ($provenanceText.capabilityMask -cne [string]$capabilities.requiredCapabilityMask) {
        throw "Firmware provenance capabilityMask must exactly match $($capabilities.requiredCapabilityMask)"
    }
    if ($provenanceText.sourceCommit -cnotmatch '^[0-9a-f]{7,40}$') {
        throw "Firmware provenance sourceCommit must be a 7-40 character lowercase Git object id"
    }
    # PS 5.1 may materialize ISO strings as DateTime while PS 7 normally keeps
    # them as strings. Validate the original JSON token so both shells share
    # the same canonical, fractional-second-free contract.
    $builtAtMatch = [regex]::Match($provenanceJson,
        '"builtAtUtc"\s*:\s*"([^"]*)"')
    $builtAtText = if ($builtAtMatch.Success) { $builtAtMatch.Groups[1].Value } else { "" }
    if (-not $builtAtMatch.Success -or
        $builtAtText -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') {
        throw "Firmware provenance builtAtUtc must use yyyy-MM-ddTHH:mm:ssZ"
    }
    try {
        [void][DateTimeOffset]::ParseExact(
            $builtAtText, "yyyy-MM-dd'T'HH:mm:ss'Z'",
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal)
    } catch {
        throw "Firmware provenance builtAtUtc must use yyyy-MM-ddTHH:mm:ssZ"
    }
    return [pscustomobject]@{
        Capabilities=$capabilities
        FirmwareName=$expectedName
        ProvenancePath=$provenancePath
    }
}

param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseInputDir
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$resolved = [IO.Path]::GetFullPath($ReleaseInputDir)
$driver = Join-Path $resolved "ble-driver\BLE_tcp_driver.exe"
if (-not (Test-Path -LiteralPath $driver -PathType Leaf)) {
    throw "BLE driver is not packaged at canonical path: $driver"
}
if ((Get-Item -LiteralPath $driver).Length -le 0) {
    throw "BLE driver package is empty: $driver"
}
Write-Output "BLE_DRIVER_PACKAGED=PASS"
Write-Output "BLE_DRIVER_RELEASE_PATH=$driver"

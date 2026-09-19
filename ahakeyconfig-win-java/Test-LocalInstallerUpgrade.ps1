param(
    [Parameter(Mandatory = $true)][string]$PreviousMsi,
    [Parameter(Mandatory = $true)][string]$NewMsi
)

# Read-only check of actual packages; never installs, repairs or removes products.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$installer = New-Object -ComObject WindowsInstaller.Installer
function Read-Properties([string]$path) {
    $db = $installer.OpenDatabase([IO.Path]::GetFullPath($path), 0)
    $view = $db.OpenView('SELECT `Property`, `Value` FROM `Property`')
    [void]$view.Execute()
    $properties = @{}
    while ($record = $view.Fetch()) {
        $properties[$record.StringData(1)] = $record.StringData(2)
    }
    [void]$view.Close()
    return $properties
}
function Msi-Version([string]$value) {
    # MSI ignores the fourth component even if a producer supplies one.
    return [version](($value.Split('.') | Select-Object -First 3) -join '.')
}
$previous = Read-Properties $PreviousMsi
$next = Read-Properties $NewMsi
if ((Msi-Version $next.ProductVersion) -le (Msi-Version $previous.ProductVersion)) {
    throw "Upgrade package must have a newer three-component version."
}
if ($next.ProductCode -eq $previous.ProductCode) {
    throw "Major upgrade must not reuse the installed ProductCode."
}
if ($next.UpgradeCode -ne $previous.UpgradeCode) {
    throw "UpgradeCode must remain stable to replace the previous product."
}
$db = $installer.OpenDatabase([IO.Path]::GetFullPath($NewMsi), 0)
$view = $db.OpenView('SELECT `UpgradeCode`, `VersionMax`, `ActionProperty` FROM `Upgrade`')
[void]$view.Execute()
$found = $false
while ($record = $view.Fetch()) {
    if ($record.StringData(1) -eq $previous.UpgradeCode -and
        $record.StringData(2) -eq $next.ProductVersion -and
        $record.StringData(3) -eq 'JP_UPGRADABLE_FOUND') { $found = $true }
}
[void]$view.Close()
if (-not $found) { throw "Missing upgrade detection for the previous product family." }
Write-Output "LOCAL_INSTALLER_UPGRADE=PASS ($($previous.ProductVersion) -> $($next.ProductVersion))"

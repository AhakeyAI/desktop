# Developer launcher. Normal users open the self-contained AhaKey Studio.exe.
# Real mode reconnects only the saved AhaKey using approved read-only BLE telemetry.
$ErrorActionPreference = 'Stop'
$studioRoot = $PSScriptRoot
$localSdk = Join-Path $studioRoot '.toolchain/dotnet/dotnet.exe'
if (Test-Path -LiteralPath $localSdk) {
    $env:DOTNET_ROOT = Split-Path $localSdk
    $studioDotnet = $localSdk
} else {
    $studioDotnet = (Get-Command dotnet -ErrorAction Stop).Source
}
Push-Location $studioRoot
try {
    & $studioDotnet run --project src/AhaKey.Studio/AhaKey.Studio.csproj --configuration Release
    if ($LASTEXITCODE -ne 0) { throw "Studio 2 exited with code $LASTEXITCODE" }
} finally { Pop-Location }

param([string]$Dotnet = 'dotnet')
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $studioRevision = (& git rev-parse HEAD).Trim()
    if (& git status --porcelain) { $studioRevision += '.dirty' }
    & $Dotnet publish src/AhaKey.Studio/AhaKey.Studio.csproj -c Release -r win-x64 --self-contained true -p:PublishProfile=WinX64Alpha -p:DebugType=none "-p:SourceRevisionId=$studioRevision"
    if ($LASTEXITCODE -ne 0) { throw "Alpha publish failed ($LASTEXITCODE)" }
    Copy-Item -LiteralPath docs/studio2/README.txt -Destination artifacts/AhaKeyStudio-win-x64/README.txt
    if (Test-Path -LiteralPath artifacts/AhaKeyStudio-win-x64/FirmwarePackages) { throw 'Public publish must not contain FirmwarePackages. Use a fresh output directory.' }
    Get-Item -LiteralPath 'artifacts/AhaKeyStudio-win-x64/AhaKey Studio.exe'
} finally { Pop-Location }

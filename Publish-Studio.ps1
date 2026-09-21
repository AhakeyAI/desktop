param([string]$Dotnet = 'dotnet')
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $studioRevision = (& git rev-parse HEAD).Trim()
    if (& git status --porcelain) { $studioRevision += '.dirty' }
    & $Dotnet publish src/AhaKey.Studio/AhaKey.Studio.csproj -c Release -r win-x64 --self-contained true -p:PublishProfile=WinX64Alpha -p:DebugType=none "-p:SourceRevisionId=$studioRevision"
    if ($LASTEXITCODE -ne 0) { throw "Alpha publish failed ($LASTEXITCODE)" }
    Copy-Item -LiteralPath docs/studio2-phase9/release-notes.txt -Destination artifacts/runtime/README.txt
    Copy-Item -LiteralPath LICENSE -Destination artifacts/runtime/LICENSE
    Copy-Item -LiteralPath docs/studio2-phase9/THIRD-PARTY-NOTICES.txt -Destination artifacts/runtime/THIRD-PARTY-NOTICES.txt
    Get-Item -LiteralPath 'artifacts/runtime/AhaKey Studio.exe'
} finally { Pop-Location }

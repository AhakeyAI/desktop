param([string]$Dotnet = 'dotnet', [switch]$PublicRelease)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $studioRevision = (& git rev-parse HEAD).Trim()
    if (& git status --porcelain) { $studioRevision += '.dirty' }
    $runtime = if ($PublicRelease) { 'artifacts/public-runtime' } else { 'artifacts/runtime' }
    $publishPath = Join-Path $PSScriptRoot $runtime
    & $Dotnet publish src/AhaKey.Studio/AhaKey.Studio.csproj -c Release -r win-x64 --self-contained true -p:PublishProfile=WinX64Alpha -p:DebugType=none "-p:SourceRevisionId=$studioRevision" "-p:PublicRelease=$($PublicRelease.IsPresent)" "-p:PublishDir=$publishPath/"
    if ($LASTEXITCODE -ne 0) { throw "Alpha publish failed ($LASTEXITCODE)" }
    $notes = if ($PublicRelease) { 'docs/studio2-phase9/public-release.md' } else { 'docs/studio2-phase9/release-notes.txt' }
    Copy-Item -LiteralPath $notes -Destination "$runtime/README.txt"
    Copy-Item -LiteralPath LICENSE -Destination "$runtime/LICENSE"
    Copy-Item -LiteralPath docs/studio2-phase9/THIRD-PARTY-NOTICES.txt -Destination "$runtime/THIRD-PARTY-NOTICES.txt"
    if ($PublicRelease -and (Get-ChildItem $publishPath -Recurse -File | Where-Object { $_.Extension -eq '.hex' -or $_.FullName -match 'FirmwarePackages' })) { throw 'Public output contains restricted firmware assets.' }
    Get-Item -LiteralPath "$runtime/AhaKey Studio.exe"
} finally { Pop-Location }

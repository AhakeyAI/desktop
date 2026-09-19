param([string]$CscPath)
$ErrorActionPreference = 'Stop'
if (-not $CscPath) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $CscPath = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\Roslyn\csc.exe' | Select-Object -First 1
}
if (-not $CscPath -or -not (Test-Path -LiteralPath $CscPath)) {
    throw 'Visual Studio C# compiler required; supply -CscPath.'
}
$bridgeRoot = Split-Path $PSScriptRoot -Parent
$testOutput = Join-Path $bridgeRoot 'bin\tests'
New-Item -ItemType Directory -Force -Path $testOutput | Out-Null
$testExe = Join-Path $testOutput 'PhysicalStatusTests.exe'
& $CscPath /nologo /target:exe /warnaserror+ "/out:$testExe" `
    (Join-Path $bridgeRoot 'Protocol.cs') (Join-Path $bridgeRoot 'TcpServer.cs') `
    (Join-Path $PSScriptRoot 'PhysicalStatusTests.cs')
if ($LASTEXITCODE -ne 0) { throw 'Bridge regression test compilation failed.' }
& $testExe
if ($LASTEXITCODE -ne 0) { throw 'Bridge physical status regression failed.' }

param([string]$CscPath, [string]$PreviewPath = "")
$ErrorActionPreference = 'Stop'
if (-not $CscPath) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $CscPath = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\Roslyn\csc.exe' | Select-Object -First 1
}
if (-not $CscPath -or -not (Test-Path -LiteralPath $CscPath)) { throw 'Visual Studio C# compiler required.' }
$bridge = Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\Release\BLE_tcp_driver.exe'
if (-not (Test-Path -LiteralPath $bridge)) { throw 'Build the Release bridge first.' }
$output = Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\tests'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$exe = Join-Path $output 'LocalizationTests.exe'
& $CscPath /nologo /warnaserror+ /target:exe "/out:$exe" /r:System.Windows.Forms.dll /r:System.Drawing.dll (Join-Path $PSScriptRoot 'LocalizationTests.cs')
if ($LASTEXITCODE -ne 0) { throw 'Localization test compilation failed.' }
$arguments = @($bridge)
if ($PreviewPath) { $arguments += $PreviewPath }
& $exe @arguments
if ($LASTEXITCODE -ne 0) { throw 'Bridge localization regression failed.' }

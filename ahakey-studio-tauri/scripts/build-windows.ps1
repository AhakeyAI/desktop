[CmdletBinding()]
param([switch]$DebugBuild)
$ErrorActionPreference = 'Stop'
$clientRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $clientRoot
$previousLib = $env:SHERPA_ONNX_LIB_DIR
$previousJobs = $env:CARGO_BUILD_JOBS
try {
    $env:SHERPA_ONNX_LIB_DIR = & .\crates\speech\scripts\prepare-runtime.ps1
    $env:CARGO_BUILD_JOBS = '6'
    & pnpm install --frozen-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Dependency restore failed' }
    & pnpm build
    if ($LASTEXITCODE -ne 0) { throw 'Frontend build failed' }
    $buildArgs = @('build', '--locked', '--manifest-path', 'src-tauri/Cargo.toml', '--features', 'custom-protocol')
    if (-not $DebugBuild) { $buildArgs += '--release' }
    & cargo @buildArgs
    if ($LASTEXITCODE -ne 0) { throw 'Rust build failed' }
    $profile = if ($DebugBuild) { 'debug' } else { 'release' }
    $version = (Get-Content -Raw package.json | ConvertFrom-Json).version
    $bundle = Join-Path $clientRoot "output/AhaKey-Studio-Rust-$version-windows-x64-$profile"
    if (Test-Path -LiteralPath $bundle) { throw "Output already exists; preserve it and choose a new version or move it explicitly: $bundle" }
    New-Item -ItemType Directory -Path $bundle | Out-Null
    Copy-Item -LiteralPath "src-tauri/target/$profile/ahakey-desktop.exe" -Destination $bundle
    $dlls = @(Get-ChildItem -LiteralPath $env:SHERPA_ONNX_LIB_DIR -Filter '*.dll' -File)
    if ($dlls.Count -ne 4) { throw 'Expected all four pinned native ASR DLLs' }
    foreach ($dll in $dlls) { Copy-Item -LiteralPath $dll.FullName -Destination $bundle }
    Copy-Item -LiteralPath 'crates/speech/runtime/licenses' -Destination $bundle -Recurse
    Copy-Item -LiteralPath 'README.md' -Destination $bundle
    Compress-Archive -LiteralPath $bundle -DestinationPath "$bundle.zip"
    Get-FileHash -LiteralPath "$bundle.zip" -Algorithm SHA256
    Write-Output "Launch: $bundle\ahakey-desktop.exe"
} finally {
    $env:SHERPA_ONNX_LIB_DIR = $previousLib
    $env:CARGO_BUILD_JOBS = $previousJobs
    Pop-Location
}

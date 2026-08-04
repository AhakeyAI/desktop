# Build script for Windows PowerShell
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host "==> Installing UI dependencies..."
Set-Location ui
npm install
Write-Host "==> Building UI..."
npm run build
Set-Location ..

Write-Host "==> Building Rust release..."
Set-Location src-tauri
cargo build --release
Set-Location ..

Write-Host ""
Write-Host "==> Build complete!"
Write-Host "Executable: $Root\src-tauri\target\release\ahakey-studio.exe"

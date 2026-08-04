# AhaKey Studio - Clean Restart
# Usage: powershell -File .\scripts\restart-clean.ps1
# Effect: kill leftover procs -> clean WebView2/Vite cache -> start .exe -> capture log

$ErrorActionPreference = 'Stop'

# ===== Config =====
$ExePath   = 'E:\RustData\cargo-target\release\ahakey-studio.exe'
$LogPath   = Join-Path $env:USERPROFILE 'Desktop\ahakey-test.log'
$Trash     = 'C:\Users\anpx\.minimax\bin\mavis-trash.cmd'
$LogFilter = 'ahakey_studio=debug,btleplug=info,info'

# ===== 1. Kill leftover procs =====
Write-Host '[1/4] Killing leftover ahakey-studio / WebView2 processes...' -ForegroundColor Cyan
$procs = @('ahakey-studio', 'msedgewebview2')
foreach ($name in $procs) {
    $list = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($list) {
        foreach ($p in $list) {
            Write-Host ("  Stopping PID " + $p.Id + " (" + $name + ")")
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host ("  (no " + $name + " running)")
    }
}
Start-Sleep -Seconds 2

# ===== 2. Clean WebView2 cache =====
Write-Host ''
Write-Host '[2/4] Cleaning WebView2 cache...' -ForegroundColor Cyan
$cacheDirs = @(
    (Join-Path $env:LOCALAPPDATA 'com.ahakey.studio.dev2'),
    (Join-Path $env:LOCALAPPDATA 'com.ahakey.studio')
)
foreach ($d in $cacheDirs) {
    if (Test-Path $d) {
        $size = (Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        Write-Host ("  trash: " + $d + " (" + [math]::Round($size/1MB, 1) + " MB)")
        & $Trash $d
        if (Test-Path $d) {
            Write-Host '  WARN: still exists, .exe may not have fully exited. Retrying...' -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            & $Trash $d
        }
    } else {
        Write-Host ("  (no " + $d + ")")
    }
}

# ===== 3. Clean Vite cache (optional) =====
Write-Host ''
Write-Host '[3/4] Cleaning Vite cache...' -ForegroundColor Cyan
$repoRoot = Split-Path -Parent $PSScriptRoot
$viteCache = Join-Path $repoRoot 'ui\node_modules\.vite'
if (Test-Path $viteCache) {
    Write-Host ("  trash: " + $viteCache)
    & $Trash $viteCache
} else {
    Write-Host '  (no .vite cache)'
}

# ===== 4. Start .exe =====
Write-Host ''
Write-Host '[4/4] Starting .exe...' -ForegroundColor Cyan
if (-not (Test-Path $ExePath)) {
    Write-Host ("  ERROR: .exe not found: " + $ExePath) -ForegroundColor Red
    Write-Host '  Hint: run cargo build --release first' -ForegroundColor Yellow
    exit 1
}
Write-Host ("  exe:   " + $ExePath)
Write-Host ("  log:   " + $LogPath)
Write-Host ("  RUST_LOG = " + $LogFilter)
Write-Host ''
Write-Host '  Starting .exe in background (script will return immediately).' -ForegroundColor Green
Write-Host ('  To stop .exe later: Stop-Process -Name ahakey-studio -Force') -ForegroundColor Green
Write-Host ''

# Set RUST_LOG and launch .exe in background, redirect streams to log file
$env:RUST_LOG = $LogFilter
$proc = Start-Process -FilePath $ExePath `
    -RedirectStandardOutput $LogPath `
    -RedirectStandardError "$LogPath.err" `
    -NoNewWindow `
    -PassThru
Write-Host ('  Started .exe PID: ' + $proc.Id)
Write-Host ('  Log:  ' + $LogPath)
Write-Host ('  Err:  ' + $LogPath + '.err')

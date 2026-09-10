[CmdletBinding()]
param([string]$RuntimeDirectory = (Join-Path $PSScriptRoot '..\runtime'))
$ErrorActionPreference = 'Stop'
if (-not [System.Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    throw 'This preparation script supports Windows x64. See README for other platforms.'
}
$runtimeRoot = [System.IO.Path]::GetFullPath($RuntimeDirectory)
[System.IO.Directory]::CreateDirectory($runtimeRoot) | Out-Null
$stem = 'sherpa-onnx-v1.13.7-win-x64-shared-MT-Release-no-tts-lib'
$expected = 'ebbcb8e6ef5ba4fb2444810fb7cc8dc0154e66f84a2101bf7c5cbcc16ce497a9'
$archive = Join-Path $runtimeRoot "$stem.tar.bz2"
if (-not (Test-Path -LiteralPath $archive)) {
    $temporary = Join-Path $runtimeRoot ([guid]::NewGuid().ToString() + '.part')
    try {
        Invoke-WebRequest -Uri "https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.7/$stem.tar.bz2" -OutFile $temporary
        if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'Native runtime archive SHA256 mismatch' }
        Move-Item -LiteralPath $temporary -Destination $archive
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'Cached native runtime archive SHA256 mismatch' }
# Always restore files from the verified archive: a directory-existing check
# alone would allow a modified DLL from a prior local extraction to be bundled.
& tar -xf $archive -C $runtimeRoot
if ($LASTEXITCODE -ne 0) { throw 'Cannot extract verified native runtime archive' }
$lib = Join-Path $runtimeRoot ($stem + '\lib')
if (-not (Test-Path -LiteralPath (Join-Path $lib 'sherpa-onnx-c-api.lib'))) { throw "Runtime import library missing: $lib" }
$notices = Join-Path $runtimeRoot 'licenses'
[System.IO.Directory]::CreateDirectory($notices) | Out-Null
Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..\licenses') -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $notices -Force
}
$ortNotices = Join-Path $notices 'onnxruntime-ThirdPartyNotices.txt'
$noticeHash = '0e07b95f3a8d6230037707c5c4a2b554d12c4cb67369669ac255635528ffcee2'
if (-not (Test-Path -LiteralPath $ortNotices)) {
    $noticeTemporary = Join-Path $notices ([guid]::NewGuid().ToString() + '.part')
    try {
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/microsoft/onnxruntime/v1.27.1/ThirdPartyNotices.txt' -OutFile $noticeTemporary
        if ((Get-FileHash -LiteralPath $noticeTemporary -Algorithm SHA256).Hash.ToLowerInvariant() -ne $noticeHash) { throw 'ONNX Runtime notices SHA256 mismatch' }
        Move-Item -LiteralPath $noticeTemporary -Destination $ortNotices
    } finally { if (Test-Path -LiteralPath $noticeTemporary) { Remove-Item -LiteralPath $noticeTemporary } }
}
if ((Get-FileHash -LiteralPath $ortNotices -Algorithm SHA256).Hash.ToLowerInvariant() -ne $noticeHash) { throw 'Cached ONNX Runtime notices SHA256 mismatch' }
# Return a path, not an environment mutation. The caller scopes this to its build.
Write-Output $lib

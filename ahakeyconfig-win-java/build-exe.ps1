param(
    [string]$BaselineAppDir = (Join-Path $env:ProgramFiles "AhaKeyStudio\app"),
    [switch]$Launch
)

# Historical compatibility entry point. Development previews must use the
# installed release baseline and the class allowlist; compiling the entire
# development source tree would replace the working voice implementation.
& (Join-Path $PSScriptRoot "preview-part3-release-overlay.ps1") `
    -BaselineAppDir $BaselineAppDir `
    -Launch:$Launch
exit $LASTEXITCODE

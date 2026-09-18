param(
    [string]$BaselineAppDir = (Join-Path $env:ProgramFiles "AhaKeyStudio\app"),
    [switch]$Launch
)

# LEGACY / NON-RELEASE: this entry point previously produced a class overlay.
# It is intentionally unsupported for current production builds and never
# invokes preview-part3-release-overlay.ps1. Use build-installer.ps1 or
# build-release-installer.ps1 after `mvn clean package` instead.
Write-Error "build-exe.ps1 is legacy/non-release and unsupported for current production builds. Use build-installer.ps1 or build-release-installer.ps1 with the complete Maven JAR."
exit 2

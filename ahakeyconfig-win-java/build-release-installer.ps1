param(
    [string]$BaselineInstallDir = (Join-Path $env:ProgramFiles "AhaKeyStudio"),
    [string]$FirmwareHex = "",
    [string]$AppVersion = "",
    [string]$FirmwareVersion = "1.4.0",
    [string]$WchIspBundleDir = "",
    [string]$WixBin = "",
    [string]$UpdateManifestUrl = "",
    [string]$IconPath = "",
    [switch]$IncludeLicensedWchIsp,
    [switch]$PrepareOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectDir = $PSScriptRoot
$pomPath = Join-Path $projectDir "pom.xml"
[xml]$pom = Get-Content -LiteralPath $pomPath -Raw
$pomVersion = [string]$pom.project.version

if ([string]::IsNullOrWhiteSpace($AppVersion)) {
    $tag = [string]$env:GITHUB_REF_NAME
    if ([string]::IsNullOrWhiteSpace($tag)) {
        $tag = (& git -C $projectDir describe --tags --exact-match 2>$null)
        if ($LASTEXITCODE -ne 0) {
            $tag = ""
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($tag)) {
        if ($tag -notmatch '^v(\d+\.\d+\.\d+)$') {
            throw "Release tag must use vMAJOR.MINOR.PATCH: $tag"
        }
        $AppVersion = $Matches[1]
    } else {
        $AppVersion = $pomVersion
    }
}

if ($AppVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "AppVersion must use MAJOR.MINOR.PATCH: $AppVersion"
}
if ($FirmwareVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "FirmwareVersion must use MAJOR.MINOR.PATCH: $FirmwareVersion"
}
if (-not [string]::IsNullOrWhiteSpace($UpdateManifestUrl)) {
    $updateManifestUri = [Uri]$UpdateManifestUrl
    if (-not $updateManifestUri.IsAbsoluteUri -or
        $updateManifestUri.Scheme -ne "https") {
        throw "UpdateManifestUrl must be an absolute HTTPS URL"
    }
}
if ($AppVersion -ne $pomVersion) {
    throw "Release version $AppVersion does not match pom.xml $pomVersion"
}

$baselineAppDir = Join-Path $BaselineInstallDir "app"
$baselineRuntime = Join-Path $BaselineInstallDir "runtime"
$baselineIcon = if ([string]::IsNullOrWhiteSpace($IconPath)) {
    Join-Path $BaselineInstallDir "AhaKeyStudio.ico"
} else {
    [IO.Path]::GetFullPath($IconPath)
}
$releaseRoot = Join-Path $projectDir "target\release-$AppVersion"
$inputDir = Join-Path $releaseRoot "input"
# WiX 3 still uses MAX_PATH for payload source files. Keep jpackage's work
# directory short because the bundled speech-model tree contains long names.
$jpackageTemp = Join-Path $env:TEMP "ahakey-jpackage-$AppVersion"
$installerDir = Join-Path $projectDir "installer"
$overlayScript = Join-Path $projectDir "preview-part3-release-overlay.ps1"
$windowsResourceDir = Join-Path $projectDir "packaging\windows"

if (-not (Test-Path -LiteralPath $baselineIcon -PathType Leaf)) {
    throw "Release baseline icon is missing: $baselineIcon"
}
$requiredWindowsResources = @("main.wxs", "ui.wxf")
foreach ($resourceName in $requiredWindowsResources) {
    $resourcePath = Join-Path $windowsResourceDir $resourceName
    if (-not (Test-Path -LiteralPath $resourcePath -PathType Leaf)) {
        throw "Windows installer resource is missing: $resourcePath"
    }
}

# Destructive cleanup is restricted to this exact project-owned build folder.
$resolvedProject = [IO.Path]::GetFullPath($projectDir)
$resolvedRelease = [IO.Path]::GetFullPath($releaseRoot)
if (-not $resolvedRelease.StartsWith($resolvedProject, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe release output path: $resolvedRelease"
}
if (Test-Path -LiteralPath $releaseRoot) {
    # The previous WiX attempt may have created paths beyond MAX_PATH.
    # The target was validated above as project-owned before using the
    # extended-length prefix for cleanup.
    Remove-Item -LiteralPath ("\\?\" + $resolvedRelease) -Recurse -Force
}
if (Test-Path -LiteralPath $jpackageTemp) {
    $resolvedTempRoot = [IO.Path]::GetFullPath($env:TEMP)
    $resolvedJpackageTemp = [IO.Path]::GetFullPath($jpackageTemp)
    if (-not $resolvedJpackageTemp.StartsWith(
        $resolvedTempRoot, [StringComparison]::OrdinalIgnoreCase
    ) -or [IO.Path]::GetFileName($resolvedJpackageTemp) -ne "ahakey-jpackage-$AppVersion") {
        throw "Unsafe jpackage temporary path: $resolvedJpackageTemp"
    }
    Remove-Item -LiteralPath $resolvedJpackageTemp -Recurse -Force
}
New-Item -ItemType Directory -Force -Path `
    $inputDir, (Join-Path $inputDir "lib"), (Join-Path $inputDir "models") |
    Out-Null

& $overlayScript -BaselineAppDir $baselineAppDir -OutputRoot (Join-Path $releaseRoot "overlay")
$overlayJar = Get-ChildItem -LiteralPath (Join-Path $releaseRoot "overlay") `
    -Recurse -Filter "ahakey-studio-1.0.0-part3-preview.jar" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $overlayJar) {
    throw "Validated overlay JAR was not produced."
}

$releaseJar = Join-Path $inputDir "ahakey-studio-$AppVersion.jar"
Copy-Item -LiteralPath $overlayJar -Destination $releaseJar
Get-ChildItem -LiteralPath (Join-Path $baselineAppDir "lib") |
    Copy-Item -Destination (Join-Path $inputDir "lib") -Recurse
Get-ChildItem -LiteralPath (Join-Path $baselineAppDir "models") |
    Copy-Item -Destination (Join-Path $inputDir "models") -Recurse

$bleDriver = @(
    (Join-Path $baselineAppDir "BLE_tcp_driver.exe"),
    (Join-Path $projectDir "BLE_tcp_driver.exe")
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($bleDriver) {
    Copy-Item -LiteralPath $bleDriver -Destination $inputDir
}

if (-not [string]::IsNullOrWhiteSpace($FirmwareHex)) {
    if (-not (Test-Path -LiteralPath $FirmwareHex)) {
        throw "Firmware HEX does not exist: $FirmwareHex"
    }
    $firmwareDir = Join-Path $inputDir "firmware"
    New-Item -ItemType Directory -Force -Path $firmwareDir | Out-Null
    Copy-Item -LiteralPath $FirmwareHex -Destination `
        (Join-Path $firmwareDir "AhaKey-X1-firmware-$FirmwareVersion-ch582.hex")
}

if ($IncludeLicensedWchIsp) {
    if ([string]::IsNullOrWhiteSpace($WchIspBundleDir) -or
        -not (Test-Path -LiteralPath $WchIspBundleDir -PathType Container)) {
        throw "A licensed WCHISP CH57x-59x bundle directory is required."
    }
    $wchDir = Join-Path $inputDir "tools\wchisp"
    New-Item -ItemType Directory -Force -Path $wchDir | Out-Null
    Get-ChildItem -LiteralPath $WchIspBundleDir -Force |
        Where-Object { $_.Name -ne "CONFIG_CH57X59X.WCH" } |
        Copy-Item -Destination $wchDir -Recurse
    $wchConfig = Join-Path $WchIspBundleDir "CONFIG_CH57X59X.WCH"
    $excludedConfig = Join-Path $wchDir "CONFIG_CH57X59X.WCH.excluded"
    if (Test-Path -LiteralPath $wchConfig -PathType Leaf) {
        Copy-Item -LiteralPath $wchConfig -Destination $excludedConfig
    }
    if (-not (Test-Path -LiteralPath `
        (Join-Path $wchDir "WCHISPTool_CH57x-59x.exe"))) {
        throw "WCHISP bundle does not contain WCHISPTool_CH57x-59x.exe at its root."
    }
    if (Test-Path -LiteralPath (Join-Path $wchDir "CONFIG_CH57X59X.WCH")) {
        throw "Mutable WCHISP UI state must not be bundled into the release."
    }
    if (-not (Test-Path -LiteralPath $excludedConfig -PathType Leaf)) {
        throw "WCHISP bundle is missing CONFIG_CH57X59X.WCH.excluded."
    }
}

$requiredModels = @(
    "encoder.int8.onnx",
    "decoder.int8.onnx",
    "silero_vad.onnx",
    "tokens.txt"
)
foreach ($name in $requiredModels) {
    if (-not (Test-Path -LiteralPath (Join-Path $inputDir "models\$name"))) {
        throw "Release voice model is missing: $name"
    }
}
if (Test-Path -LiteralPath (Join-Path $inputDir "models\model_q8.onnx")) {
    throw "Unsafe model_q8.onnx was introduced into the release input."
}

Write-Output "RELEASE_INPUT_VALIDATION=OK"
Write-Output "Prepared input: $inputDir"
if ($PrepareOnly) {
    exit 0
}
if ([string]::IsNullOrWhiteSpace($FirmwareHex)) {
    throw "A release installer requires -FirmwareHex with the built CH582 $FirmwareVersion firmware."
}

$jdkCandidates = @()
if ($env:JAVA_HOME) {
    $jdkCandidates += Join-Path $env:JAVA_HOME "bin"
}
$jdkCandidates += Join-Path $env:LOCALAPPDATA `
    "Temp\ahakey-part3-toolchain\jdk-17\bin"
$jdkBin = $jdkCandidates |
    Where-Object { Test-Path -LiteralPath (Join-Path $_ "jpackage.exe") } |
    Select-Object -First 1
if (-not $jdkBin) {
    throw "JDK 17 jpackage.exe is required. Set JAVA_HOME to a JDK 17 installation."
}
$jpackage = Join-Path $jdkBin "jpackage.exe"
$wix = @(
    $WixBin,
    "C:\Program Files (x86)\WiX Toolset v3.14\bin",
    "C:\Program Files\WiX Toolset v3.14\bin",
    "C:\Program Files (x86)\WiX Toolset v3.11\bin"
) | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_) -and
    (Test-Path -LiteralPath (Join-Path $_ "candle.exe"))
} | Select-Object -First 1
if (-not $wix) {
    throw "WiX Toolset 3.x is required for the Windows .exe installer. Release input is ready and validated."
}
$env:PATH = "$wix;$env:PATH"
New-Item -ItemType Directory -Force -Path $installerDir | Out-Null

$jpackageArgs = @(
    "--type", "exe",
    "--name", "AhaKeyStudio",
    "--app-version", $AppVersion,
    "--vendor", "AhaKey",
    "--description", "AhaKey Studio - Keyboard Configuration Tool",
    "--icon", $baselineIcon,
    "--input", $inputDir,
    "--main-jar", "ahakey-studio-$AppVersion.jar",
    "--main-class", "com.example.ahakey.App",
    "--dest", $installerDir,
    "--temp", $jpackageTemp,
    "--runtime-image", $baselineRuntime,
    "--install-dir", "AhaKeyStudio",
    "--resource-dir", $windowsResourceDir,
    "--win-dir-chooser",
    "--win-shortcut",
    "--win-menu",
    "--win-menu-group", "AhaKey",
    # Keep the safe upgrade line introduced in 1.2.5. The custom WiX UI lets
    # the user choose a parent directory while INSTALLDIR always remains the
    # AhaKeyStudio child directory, so uninstall cannot own the broad parent.
    "--win-upgrade-uuid", "8842dbef-62f7-49ac-af0f-9447198265f3",
    "--java-options", "--add-opens=javafx.graphics/com.sun.javafx.application=ALL-UNNAMED",
    "--java-options", "--add-opens=javafx.controls/com.sun.javafx.scene.control=ALL-UNNAMED",
    "--java-options", "--add-opens=javafx.fxml/com.sun.javafx.fxml=ALL-UNNAMED",
    "--java-options", "-Dprism.allowhidpi=true",
    "--java-options", "-Dapp.version=$AppVersion"
)
if (-not [string]::IsNullOrWhiteSpace($UpdateManifestUrl)) {
    $jpackageArgs += @(
        "--java-options",
        "-Dahakey.update.manifestUrl=$UpdateManifestUrl"
    )
}

& $jpackage @jpackageArgs
if ($LASTEXITCODE -ne 0) {
    throw "jpackage failed with exit code $LASTEXITCODE"
}

# Validate jpackage's generated WiX directory tree, not only the source
# templates. This guards against a future JDK/template change that could make
# INSTALLDIR point at the broad user-selected parent again.
$generatedConfigDir = Join-Path $jpackageTemp "config"
$generatedBundlePath = Join-Path $generatedConfigDir "bundle.wxf"
$generatedMainPath = Join-Path $generatedConfigDir "main.wxs"
$generatedUiPath = Join-Path $generatedConfigDir "ui.wxf"
foreach ($generatedResource in @(
    $generatedBundlePath,
    $generatedMainPath,
    $generatedUiPath
)) {
    if (-not (Test-Path -LiteralPath $generatedResource -PathType Leaf)) {
        throw "Generated Windows installer resource is missing: $generatedResource"
    }
}

$bundleXml = New-Object System.Xml.XmlDocument
$bundleXml.LoadXml([IO.File]::ReadAllText($generatedBundlePath))
$installDirNode = $bundleXml.SelectSingleNode(
    "//*[local-name()='Directory' and @Id='INSTALLDIR']"
)
if ($null -eq $installDirNode -or
    $installDirNode.GetAttribute("Name") -ne "AhaKeyStudio" -or
    $null -eq $installDirNode.ParentNode -or
    $installDirNode.ParentNode.GetAttribute("Id") -ne "ProgramFiles64Folder") {
    throw "Unsafe installer layout: INSTALLDIR must be ProgramFiles64Folder/AhaKeyStudio."
}

$generatedMain = [IO.File]::ReadAllText($generatedMainPath)
$generatedUi = [IO.File]::ReadAllText($generatedUiPath)
if ($generatedUi -notmatch 'WIXUI_INSTALLDIR"\s+Value="ProgramFiles64Folder"' -or
    $generatedUi -notmatch 'AhaKeyInstallParentDlg') {
    throw "Unsafe installer UI: the chooser must edit only the install parent."
}
if ($generatedMain -notmatch 'AHAKEY_PREVIOUS_INSTALLDIR' -or
    $generatedMain -notmatch 'AhaKeyRememberInstallDir') {
    throw "Installer upgrade-path persistence was not included."
}
Write-Output "WINDOWS_INSTALLER_LAYOUT_VALIDATION=OK"

$generated = Join-Path $installerDir "AhaKeyStudio-$AppVersion.exe"
$final = Join-Path $installerDir `
    "AhaKeyStudio-$AppVersion-windows-x64.exe"
if (-not (Test-Path -LiteralPath $generated)) {
    throw "jpackage output was not found: $generated"
}
if (Test-Path -LiteralPath $final -PathType Leaf) {
    Remove-Item -LiteralPath $final -Force
}
Move-Item -LiteralPath $generated -Destination $final
Write-Output "INSTALLER=$final"

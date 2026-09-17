param(
    [string]$BaselineInstallDir = (Join-Path $env:ProgramFiles "AhaKeyStudio"),
    [string]$FirmwareHex = "",
    [string]$AppVersion = "",
    [Parameter(Mandatory = $true)]
    [string]$FirmwareVersion,
    [string]$WchIspBundleDir = "",
    [string]$WixBin = "",
    [string]$UpdateManifestUrl = "",
    [string]$IconPath = "",
    [Alias("IncludeWchIsp")]
    [switch]$IncludeLicensedWchIsp,
    [switch]$InternalValidationOnly,
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
        # Windows PowerShell can promote native stderr to a terminating error
        # under Stop. An untagged development checkout is expected here.
        $savedErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = "SilentlyContinue"
            $tag = (& git -C $projectDir describe --tags --exact-match 2>$null)
        } finally {
            $ErrorActionPreference = $savedErrorActionPreference
        }
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
. (Join-Path $projectDir "Test-FirmwareReleaseInput.ps1")
$firmwareValidation = Assert-AhaKeyFirmwareReleaseInput `
    -ProjectDir $projectDir `
    -FirmwareVersion $FirmwareVersion `
    -FirmwareHex $FirmwareHex `
    -RequireFirmware:(-not ($PrepareOnly -or $InternalValidationOnly))
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
$baselineJar = Join-Path $baselineAppDir "ahakey-studio-1.0.0.jar"
$baselineRuntime = Join-Path $BaselineInstallDir "runtime"
$currentJar = Join-Path $projectDir "target\ahakey-studio-$AppVersion.jar"
$currentLibDir = Join-Path $projectDir "target\lib"
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
foreach ($required in @($currentJar, $currentLibDir)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Current clean-build output is missing: $required. Run mvn clean package first."
    }
}
if (-not (Test-Path -LiteralPath $baselineJar -PathType Leaf)) {
    throw "Voice release baseline JAR is missing: $baselineJar"
}
& (Join-Path $projectDir "Test-ReleaseArtifactContents.ps1") -JarPath $currentJar

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

$releaseJar = Join-Path $inputDir "ahakey-studio-$AppVersion.jar"
Copy-Item -LiteralPath $currentJar -Destination $releaseJar
Get-ChildItem -LiteralPath $currentLibDir |
    Copy-Item -Destination (Join-Path $inputDir "lib") -Recurse
Get-ChildItem -LiteralPath (Join-Path $baselineAppDir "models") |
    Copy-Item -Destination (Join-Path $inputDir "models") -Recurse

# The historical Sherpa JAR carries the Windows native runtime as embedded
# resources.  The current application JAR is intentionally kept small, so
# extract those exact, version-pinned resources into the sidecar layout that
# LibraryLoader resolves from an installed app's app/lib directory.
$sherpaNativeStage = Join-Path $inputDir "lib\sherpa-onnx\native\win-x64"
New-Item -ItemType Directory -Force -Path $sherpaNativeStage | Out-Null
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$baselineArchive = [IO.Compression.ZipFile]::OpenRead($baselineJar)
try {
    foreach ($nativeName in @(
        "onnxruntime.dll",
        "onnxruntime_providers_shared.dll",
        "sherpa-onnx-jni.dll"
    )) {
        $entryName = "sherpa-onnx/native/win-x64/$nativeName"
        $entry = $baselineArchive.GetEntry($entryName)
        if ($null -eq $entry) {
            throw "Sherpa native resource is missing from release baseline JAR: $entryName"
        }
        $destination = Join-Path $sherpaNativeStage $nativeName
        $entryStream = $entry.Open()
        $outputStream = [IO.File]::Create($destination)
        try { $entryStream.CopyTo($outputStream) }
        finally {
            $outputStream.Dispose()
            $entryStream.Dispose()
        }
    }
} finally {
    $baselineArchive.Dispose()
}
foreach ($nativeName in @(
    "onnxruntime.dll",
    "onnxruntime_providers_shared.dll",
    "sherpa-onnx-jni.dll"
)) {
    $nativePath = Join-Path $sherpaNativeStage $nativeName
    if (-not (Test-Path -LiteralPath $nativePath -PathType Leaf) -or
        (Get-Item -LiteralPath $nativePath).Length -eq 0) {
        throw "Sherpa native sidecar was not staged: $nativePath"
    }
}
Write-Output "SHERPA_NATIVE_PACKAGED=PASS"

$bleDriver = @(
    (Join-Path $projectDir "BLE_tcp_driver.exe"),
    (Join-Path $projectDir "..\BLE_tcp_bridge\bin\Release\BLE_tcp_driver.exe"),
    (Join-Path $baselineAppDir "ble-driver\BLE_tcp_driver.exe"),
    (Join-Path $baselineAppDir "BLE_tcp_driver.exe")
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $bleDriver) {
    Write-Output "BLE_DRIVER_BUILD=FAIL"
    throw "BLE_tcp_driver.exe is missing. Build BLE_tcp_bridge Release before packaging."
}
Write-Output "BLE_DRIVER_BUILD=PASS"
$bleDriverStage = Join-Path $inputDir "ble-driver"
New-Item -ItemType Directory -Force -Path $bleDriverStage | Out-Null
Copy-Item -LiteralPath $bleDriver -Destination (Join-Path $bleDriverStage "BLE_tcp_driver.exe")
if (-not (Test-Path -LiteralPath (Join-Path $bleDriverStage "BLE_tcp_driver.exe") -PathType Leaf)) {
    Write-Output "BLE_DRIVER_PACKAGED=FAIL"
    throw "BLE driver was not staged at the canonical app/ble-driver path."
}
Write-Output "BLE_DRIVER_PACKAGED=PASS"
Write-Output "BLE_DRIVER_RELEASE_PATH=$bleDriverStage\BLE_tcp_driver.exe"
& (Join-Path $projectDir "Test-BleDriverPackaging.ps1") -ReleaseInputDir $inputDir

if (-not [string]::IsNullOrWhiteSpace($FirmwareHex)) {
    $firmwareDir = Join-Path $inputDir "firmware"
    New-Item -ItemType Directory -Force -Path $firmwareDir | Out-Null
    $bundledFirmwarePath = Join-Path $firmwareDir $firmwareValidation.FirmwareName
    Copy-Item -LiteralPath $FirmwareHex -Destination $bundledFirmwarePath
    Copy-Item -LiteralPath $firmwareValidation.ProvenancePath -Destination `
        (Join-Path $firmwareDir ([IO.Path]::GetFileName($firmwareValidation.ProvenancePath)))
    if ([IO.Path]::GetFileName($bundledFirmwarePath) -cne
        "AhaKey-X1-firmware-$($firmwareValidation.Capabilities.expectedBundledVersion)-ch582.hex") {
        throw "Packaged firmware filename does not match Java BUNDLED_FIRMWARE_NAME"
    }
}

if ($IncludeLicensedWchIsp) {
    if ([string]::IsNullOrWhiteSpace($WchIspBundleDir) -or
        -not (Test-Path -LiteralPath $WchIspBundleDir -PathType Container)) {
        throw "A supplied official WCHISP CH57x-59x bundle directory is required."
    }
    foreach ($runtimeFile in @(
        "WCHISPTool_CH57x-59x.exe",
        "CH343PT.DLL",
        "WCH55xISPDLL.dll",
        "CONFIG_CH57X59X.WCH"
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $WchIspBundleDir $runtimeFile) -PathType Leaf)) {
            throw "WCHISP runtime bundle is missing: $runtimeFile"
        }
    }
    $wchDir = Join-Path $inputDir "tools\wchisp"
    New-Item -ItemType Directory -Force -Path $wchDir | Out-Null
    Get-ChildItem -LiteralPath $WchIspBundleDir -Force |
        Where-Object {
            $_.Name -notin @(
                "CONFIG_CH57X59X.WCH",
                "CONFIG_CH57X59X.WCH.excluded",
                "wchisp-runtime.json"
            )
        } |
        Copy-Item -Destination $wchDir -Recurse
    # Keep the configuration from the same vendor bundle as the executable and
    # DLLs. Clear only the five persisted firmware-path slots so developer and
    # historical paths are not redistributed. Version strings are recorded as
    # diagnostics, not treated as an artificial exact-version allowlist.
    $sourceConfig = Join-Path $WchIspBundleDir "CONFIG_CH57X59X.WCH"
    $stagedConfig = Join-Path $wchDir "CONFIG_CH57X59X.WCH"
    [byte[]]$configBytes = [IO.File]::ReadAllBytes($sourceConfig)
    if ($configBytes.Length -ne 66841) {
        throw "Unsupported WCHISP configuration size: $($configBytes.Length)"
    }
    foreach ($offset in @(36486, 37006, 37526, 63172, 63692)) {
        if ($offset -lt 0 -or $offset + 520 -gt $configBytes.Length) {
            throw "WCHISP configuration path slot is outside the file: $offset"
        }
        [Array]::Clear($configBytes, $offset, 520)
    }
    [IO.File]::WriteAllBytes($stagedConfig, $configBytes)

    $stagedExe = Join-Path $wchDir "WCHISPTool_CH57x-59x.exe"
    $stagedDriverDll = Join-Path $wchDir "CH343PT.DLL"
    $stagedIspDll = Join-Path $wchDir "WCH55xISPDLL.dll"
    $toolVersion = [string](Get-Item -LiteralPath $stagedExe).VersionInfo.FileVersion
    $driverVersion = [string](Get-Item -LiteralPath $stagedDriverDll).VersionInfo.FileVersion
    $ispVersion = [string](Get-Item -LiteralPath $stagedIspDll).VersionInfo.FileVersion
    foreach ($versionEvidence in @($toolVersion, $driverVersion, $ispVersion)) {
        if ([string]::IsNullOrWhiteSpace($versionEvidence)) {
            throw "WCHISP runtime component lacks file-version evidence."
        }
    }
    $exeHash = (Get-FileHash -LiteralPath $stagedExe -Algorithm SHA256).Hash.ToLowerInvariant()
    $driverHash = (Get-FileHash -LiteralPath $stagedDriverDll -Algorithm SHA256).Hash.ToLowerInvariant()
    $ispHash = (Get-FileHash -LiteralPath $stagedIspDll -Algorithm SHA256).Hash.ToLowerInvariant()
    $configHash = (Get-FileHash -LiteralPath $stagedConfig -Algorithm SHA256).Hash.ToLowerInvariant()
    $runtimeMetadata = [ordered]@{
        bundleId = "wchisp-ch57x59x-packaged"
        toolVersion = $toolVersion.Trim()
        ispDllVersion = $ispVersion.Trim()
        driverDllVersion = $driverVersion.Trim()
        configContractVersion = "sanitized-five-path-slots-v1"
        configLayoutFingerprint = $configHash
        supportedChipFamily = "CH57x/CH59x"
        supportedModel = "CH582"
        source = "User-supplied official WCHISP bundle; redistribution authorization not verified"
        provenance = "Versions and file hashes recorded during packaging; persisted firmware paths removed"
        exeSha256 = $exeHash
        ch343Sha256 = $driverHash
        ispDllSha256 = $ispHash
        configSha256 = $configHash
    }
    $metadataJson = $runtimeMetadata | ConvertTo-Json
    [IO.File]::WriteAllText(
        (Join-Path $wchDir "wchisp-runtime.json"),
        $metadataJson,
        (New-Object Text.UTF8Encoding($false))
    )
    if (-not (Test-Path -LiteralPath `
        (Join-Path $wchDir "WCHISPTool_CH57x-59x.exe"))) {
        throw "WCHISP bundle does not contain WCHISPTool_CH57x-59x.exe at its root."
    }
    & (Join-Path $projectDir "Test-WchIspReleasePrivacy.ps1") -RootPath $wchDir
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
& (Join-Path $projectDir "Test-ReleaseArtifactContents.ps1") `
    -JarPath $releaseJar -ReleaseInputDir $inputDir

Write-Output $(if ([string]::IsNullOrWhiteSpace($FirmwareHex)) {
    if ($InternalValidationOnly) { "RELEASE_INPUT_VALIDATION=INTERNAL_WITHOUT_FORMAL_FIRMWARE" }
    else { "RELEASE_INPUT_VALIDATION=PREPARED_WITHOUT_FIRMWARE" }
} else {
    "RELEASE_INPUT_VALIDATION=OK"
})
if ($InternalValidationOnly -and [string]::IsNullOrWhiteSpace($FirmwareHex)) {
    Write-Output "FIRMWARE_BUNDLED=NO_UNVERIFIED"
}
Write-Output "Prepared input: $inputDir"
if ($PrepareOnly) {
    exit 0
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
    # The Sherpa API performs its own native lookup when OnlineRecognizer is
    # constructed.  Keep that lookup on the same app-relative sidecar tree
    # staged above instead of relying on the launcher process' java.library.path.
    "--java-options", '-Dsherpa_onnx.native.path=$APPDIR\lib\sherpa-onnx\native\win-x64',
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
    "AhaKey-Studio-$AppVersion-Setup.exe"
if (-not (Test-Path -LiteralPath $generated)) {
    throw "jpackage output was not found: $generated"
}
if (Test-Path -LiteralPath $final -PathType Leaf) {
    Remove-Item -LiteralPath $final -Force
}
Move-Item -LiteralPath $generated -Destination $final
$signature = Get-AuthenticodeSignature -LiteralPath $final
if (-not $InternalValidationOnly -and
    $signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    throw "Formal release installer must have a Valid Authenticode signature; status=$($signature.Status)"
}
if ($signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid) {
    Write-Output "AUTHENTICODE_SIGNATURE=VALID"
    Write-Output "SIGNED=YES"
} else {
    Write-Output "AUTHENTICODE_SIGNATURE=$($signature.Status)"
    Write-Output "SIGNED=NO"
}
if ($InternalValidationOnly) {
    Write-Output "PACKAGE_MODE=INTERNAL_INSTALL_VALIDATION_ONLY"
}
Write-Output "INSTALLER=$final"
$stableFinal = Join-Path $installerDir "AhaKey-Studio-Setup.exe"
Copy-Item -LiteralPath $final -Destination $stableFinal -Force
Write-Output "INSTALLER_STABLE=$stableFinal"

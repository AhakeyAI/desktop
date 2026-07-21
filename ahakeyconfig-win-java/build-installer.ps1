<#
AhaKey Studio Build Script - Package JavaFX app to Windows EXE Installer
Requires: JDK 17+, Maven 3.6+, NSIS (for --type exe)

Usage: .\build-installer.ps1
#>

$ErrorActionPreference = "Continue"

$ProjectName = "AhaKeyStudio"
$Version = "1.0.0"
$MainClass = "com.example.ahakey.App"
$TargetDir = Join-Path $PSScriptRoot "target"
$InstallerDir = Join-Path $PSScriptRoot "installer"  # 移到项目根目录，避免被 Maven clean 清理
$TempDir = "$TargetDir\jpackage-input"
$RuntimeDir = "$TargetDir\runtime"
$ResourceDir = "$TargetDir\jpackage-resources"
$IconPath = Join-Path $PSScriptRoot "VibeCodeKeyboard.ico"

function Write-Status($Message, $Color) {
    Write-Host "[$(Get-Date -Format HH:mm:ss)] " -NoNewline
    Write-Host $Message -ForegroundColor $Color
}

Write-Status "AhaKey Studio Installer Build v1.0" Cyan
Write-Status "====================================" Cyan

# Ensure WiX tools are on PATH (jpackage --type exe requires candle.exe/light.exe)
$wixPaths = @(
    "C:\Program Files (x86)\WiX Toolset v3.14\bin",
    "C:\Program Files\WiX Toolset v3.14\bin",
    "C:\Program Files (x86)\WiX Toolset v3.11\bin"
)
foreach ($p in $wixPaths) {
    if ((Test-Path $p) -and $env:PATH -notlike "*$p*") {
        $env:PATH = "$p;$env:PATH"
    }
}

# Build project (must run from script directory so Maven finds pom.xml)
Set-Location $PSScriptRoot
Write-Status "Building project..." Cyan
& mvn "-Dmaven.repo.local=.m2repo" package -DskipTests

if ($LASTEXITCODE -ne 0) {
    Write-Status "ERROR: Maven build failed" Red
    exit 1
}
Write-Status "Maven build successful" Green

# Ensure installer directory exists
if (-not (Test-Path $InstallerDir)) {
    New-Item -ItemType Directory -Path $InstallerDir | Out-Null
}

# Create clean temporary input directory
Write-Status "Preparing clean input directory..." Cyan
if (Test-Path $TempDir) {
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path "$TempDir\lib" | Out-Null
if (Test-Path $ResourceDir) {
    Remove-Item -Path $ResourceDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $ResourceDir | Out-Null
Copy-Item -Path $IconPath -Destination "$ResourceDir\$ProjectName.ico" -Force

$jarPath = "$TargetDir\ahakey-studio-$Version.jar"

# Check if local model is enabled
$modelEnabled = $false
$propsFile = Join-Path $PSScriptRoot "src/main/resources/model_config.properties"
if (Test-Path $propsFile) {
    $match = Select-String -Path $propsFile -Pattern '^\s*model\.enabled\s*=\s*(.+)$'
    if ($match) {
        $modelEnabled = $match.Matches[0].Groups[1].Value.Trim() -eq 'true'
    }
}

if ($modelEnabled) {
    Write-Status "model.enabled=true: Including model files and ONNX runtime" Cyan
} else {
    Write-Status "model.enabled=false: EXCLUDING model files and ONNX runtime" Yellow
}

# Copy only required files
Copy-Item -Path $jarPath -Destination $TempDir
Copy-Item -Path "$TargetDir\lib\*.jar" -Destination "$TempDir\lib"

if ($modelEnabled) {
    Write-Status "Copying SenseVoice model files..." Cyan
    New-Item -ItemType Directory -Path "$TempDir\models" | Out-Null
    Copy-Item -Path (Join-Path $PSScriptRoot "src/main/resources/models/model_q8.onnx") -Destination "$TempDir\models" -Force
    Copy-Item -Path (Join-Path $PSScriptRoot "src/main/resources/models/tokens.txt") -Destination "$TempDir\models" -Force
    Write-Status "Model files copied successfully" Green
} else {
    Write-Status "Removing onnxruntime from lib..." Yellow
    Remove-Item -Path "$TempDir\lib\onnxruntime*.jar" -Force -ErrorAction SilentlyContinue
    Write-Status "Removing model files from JAR..." Yellow
    $jarName = Split-Path $jarPath -Leaf
    $zipPath = "$TempDir\$jarName"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Update')
    $entries = $zip.Entries | Where-Object { $_.FullName -like 'models/*' }
    foreach ($entry in $entries) { $entry.Delete() }
    $zip.Dispose()
    Write-Status "onnxruntime + model files removed from package (saved ~233MB)" Green
}

Write-Status "Input directory ready" Green

# Copy BLE TCP bridge driver
$bleCandidates = @(
    (Join-Path $PSScriptRoot "BLE_tcp_driver.exe"),
    (Join-Path $PSScriptRoot "..\BLE_tcp_driver.exe"),
    (Join-Path $PSScriptRoot "..\ahakeyconfig-win\BLE_tcp_bridge_for_vibe_code-master (1)\BLE_tcp_bridge_for_vibe_code-master\dist\BLE_tcp_driver.exe")
)
$bleExeSource = $bleCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($bleExeSource) {
    Write-Status "Copying BLE TCP driver to input dir..." Cyan
    Copy-Item -Path $bleExeSource -Destination "$TempDir\BLE_tcp_driver.exe" -Force
    Write-Status "BLE driver copied" Green
} else {
    Write-Status "WARNING: BLE driver not found, skipping" Yellow
}

# Create custom runtime using jlink
Write-Status "Creating custom runtime using jlink..." Cyan
if (Test-Path $RuntimeDir) {
    Remove-Item -Path $RuntimeDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Detect JDK version for --compress flag (JDK 21+ uses zip-6, JDK 17 uses 2)
$javaVersion = (& java -version 2>&1 | Select-String 'version "(\d+)' | ForEach-Object { $_.Matches[0].Groups[1].Value })
$compressArg = if ([int]$javaVersion -ge 21) { "zip-6" } else { "2" }
Write-Status "JDK $javaVersion detected, using --compress=$compressArg" Cyan

$jlinkArgs = @(
    "--module-path", "$TargetDir\lib",
    "--add-modules", "javafx.controls,javafx.fxml,javafx.graphics,java.base,java.logging,java.desktop,java.net.http,java.sql,java.naming,java.xml",
    "--output", $RuntimeDir,
    "--strip-debug",
    "--no-header-files",
    "--no-man-pages",
    "--compress", $compressArg
)

& jlink @jlinkArgs

if ($LASTEXITCODE -ne 0) {
    Write-Status "ERROR: jlink failed" Red
    exit 1
}
Write-Status "Custom runtime created successfully" Green

# Create EXE installer using jpackage
Write-Status "Creating EXE installer (requires NSIS)..." Cyan

# Generate timestamp for version (format: yyyyMMddHHmmss)
$timestamp = Get-Date -Format "yyyyMMddHHmmss"

$jpackageArgs = @(
    "--type", "exe",
    "--name", $ProjectName,
    "--app-version", $Version,
    "--vendor", "AhaKey",
    "--description", "AhaKey Studio - Keyboard Configuration Tool",
    "--copyright", "2024 AhaKey",
    "--icon", $IconPath,
    "--resource-dir", $ResourceDir,
    "--input", $TempDir,
    "--main-jar", (Split-Path $jarPath -Leaf),
    "--main-class", $MainClass,
    "--dest", $InstallerDir,
    "--runtime-image", $RuntimeDir,
    "--win-dir-chooser",
    "--win-shortcut",
    "--win-menu",
    "--win-menu-group", "AhaKey",
    "--java-options", "--add-opens=javafx.graphics/com.sun.javafx.application=ALL-UNNAMED",
    "--java-options", "--add-opens=javafx.controls/com.sun.javafx.scene.control=ALL-UNNAMED",
    "--java-options", "--add-opens=javafx.fxml/com.sun.javafx.fxml=ALL-UNNAMED",
    "--java-options", "-Dapp.version=$timestamp",
    "--verbose"
)

& jpackage @jpackageArgs

if ($LASTEXITCODE -ne 0) {
    Write-Status "ERROR: jpackage failed. Make sure NSIS is installed (https://nsis.sourceforge.io)" Red
    exit 1
}

# Cleanup temporary directories
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $RuntimeDir -Recurse -Force -ErrorAction SilentlyContinue

# Rename output to timestamp-based filename
$originalExe = "$InstallerDir\$ProjectName-$Version.exe"
$renamedExe  = "$InstallerDir\$ProjectName-$timestamp.exe"
if (Test-Path $originalExe) {
    Rename-Item -Path $originalExe -NewName "$ProjectName-$timestamp.exe"
}

Write-Status "====================================" Cyan
Write-Status "Installer build completed!" Green
Write-Status "Output: $renamedExe" Cyan

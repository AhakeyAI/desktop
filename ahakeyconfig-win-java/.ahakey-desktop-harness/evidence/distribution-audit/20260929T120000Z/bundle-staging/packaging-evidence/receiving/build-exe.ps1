<#
AhaKey Studio Build Script - Package JavaFX app to Windows App Image
Requires: JDK 17+, Maven 3.6+

Usage: .\build-exe.ps1
#>

$ErrorActionPreference = "Continue"

$ProjectName = "AhaKeyStudio"
$Version = "1.0.0"
$MainClass = "com.example.ahakey.App"
$TargetDir = Join-Path $PSScriptRoot "target"
$InstallerDir = "$TargetDir/installer"
$TempDir = "$TargetDir/jpackage-input"
$RuntimeDir = "$TargetDir/runtime"
$ResourceDir = "$TargetDir/jpackage-resources"
$IconPath = Join-Path $PSScriptRoot "VibeCodeKeyboard.ico"

function Write-Status($Message, $Color) {
    Write-Host "[$(Get-Date -Format HH:mm:ss)] " -NoNewline
    Write-Host $Message -ForegroundColor $Color
}

Write-Status "AhaKey Studio Build Script v1.0" Cyan
Write-Status "==============================" Cyan

# Build project (must run from script directory so Maven finds pom.xml)
Set-Location $PSScriptRoot
Write-Status "Building project..." Cyan
& mvn "-Dmaven.repo.local=.m2repo" package -DskipTests

if ($LASTEXITCODE -ne 0) {
    Write-Status "ERROR: Maven build failed" Red
    exit 1
}
Write-Status "Maven build successful" Green

# Clean old installer
if (Test-Path $InstallerDir) {
    Write-Status "Removing old installer..." Yellow
    # Try to kill any running processes that might be locking the directory
    try {
        Get-Process -Name "AhaKeyStudio" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    } catch {
        # Ignore errors
    }
    # Use robocopy to delete directory (more reliable)
    $null = New-Item -ItemType Directory -Path "$TargetDir/empty_dir" -Force -ErrorAction SilentlyContinue
    robocopy "$TargetDir/empty_dir" $InstallerDir /MIR /NFL /NDL /NJH /NJS | Out-Null
    Remove-Item -Path "$TargetDir/empty_dir" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $InstallerDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Create clean temporary input directory
Write-Status "Preparing clean input directory..." Cyan
if (Test-Path $TempDir) {
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path "$TempDir/lib" | Out-Null
if (Test-Path $ResourceDir) {
    Remove-Item -Path $ResourceDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $ResourceDir | Out-Null
Copy-Item -Path $IconPath -Destination "$ResourceDir/$ProjectName.ico" -Force

$jarPath = "$TargetDir/ahakey-studio-$Version.jar"

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
Copy-Item -Path "$TargetDir/lib/*.jar" -Destination "$TempDir/lib"

if ($modelEnabled) {
    # Copy SenseVoice model files
    Write-Status "Copying SenseVoice model files..." Cyan
    New-Item -ItemType Directory -Path "$TempDir/models" | Out-Null
    Copy-Item -Path (Join-Path $PSScriptRoot "src/main/resources/models/model_q8.onnx") -Destination "$TempDir/models" -Force
    Copy-Item -Path (Join-Path $PSScriptRoot "src/main/resources/models/tokens.txt") -Destination "$TempDir/models" -Force
    Write-Status "Model files copied successfully" Green
} else {
    # Remove onnxruntime dependency from lib
    Write-Status "Removing onnxruntime from lib..." Yellow
    Remove-Item -Path "$TempDir/lib/onnxruntime*.jar" -Force -ErrorAction SilentlyContinue
    # Remove model files from JAR to reduce package size
    Write-Status "Removing model files from JAR..." Yellow
    $jarName = Split-Path $jarPath -Leaf
    $zipPath = "$TempDir/$jarName"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Update')
    $entries = $zip.Entries | Where-Object { $_.FullName -like 'models/*' }
    foreach ($entry in $entries) { $entry.Delete() }
    $zip.Dispose()
    Write-Status "onnxruntime + model files removed from package (saved ~233MB)" Green
}

Write-Status "Input directory ready" Green

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
    "--module-path", "$TargetDir/lib",
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

# Create app-image using jpackage
Write-Status "Creating App Image..." Cyan

$jpackageArgs = @(
    "--type", "app-image",
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
    "--java-options", "--add-opens=javafx.graphics/com.sun.javafx.application=ALL-UNNAMED",
    "--java-options", "--add-opens=javafx.controls/com.sun.javafx.scene.control=ALL-UNNAMED",
    "--java-options", "--add-opens=javafx.fxml/com.sun.javafx.fxml=ALL-UNNAMED",
    "--verbose"
)

& jpackage @jpackageArgs

if ($LASTEXITCODE -ne 0) {
    Write-Status "ERROR: jpackage failed" Red
    exit 1
}

Write-Status "App Image created successfully!" Green
Write-Status "Output location: $InstallerDir\$ProjectName" Cyan

# Copy BLE TCP bridge driver
$bleCandidates = @(
    ".\BLE_tcp_driver.exe",
    "..\BLE_tcp_driver.exe",
    "..\ahakeyconfig-win\BLE_tcp_bridge_for_vibe_code-master (1)\BLE_tcp_bridge_for_vibe_code-master\dist\BLE_tcp_driver.exe"
)
$bleExeSource = $bleCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($bleExeSource) {
    Write-Status "Copying BLE TCP driver..." Cyan
    Copy-Item -Path $bleExeSource -Destination "$InstallerDir\$ProjectName\BLE_tcp_driver.exe" -Force
    Write-Status "BLE driver copied to app image" Green
} else {
    Write-Status "WARNING: BLE driver not found" Yellow
    Write-Status "Run build-single-exe.bat in the BLE project first, or copy BLE_tcp_driver.exe manually." Yellow
}

# Cleanup temporary directories
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $RuntimeDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Status "==============================" Cyan
Write-Status "Build completed successfully!" Green

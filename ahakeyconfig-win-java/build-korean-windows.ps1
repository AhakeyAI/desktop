param(
    [Parameter(Mandatory = $true)][string]$RuntimeImage,
    [Parameter(Mandatory = $true)][string]$IconPath,
    [string]$JdkHome = $env:JAVA_HOME,
    [string]$WixBin = "",
    [string]$OutputRoot = "",
    [string]$PackageVersion = ""
)

# Korean community build, adapted from build-local-windows.ps1: no firmware, speech-model assets or vendor flasher are
# implied by this target. The formal release pipeline remains separate.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $PSScriptRoot "target\windows-ko"
}
[xml]$pom = Get-Content (Join-Path $PSScriptRoot "pom.xml") -Raw
$sourceVersion = [string]$pom.project.version
# Rebuilt packages must use a newer MSI version when upgrading an installation.
# A fourth component is intentionally rejected: MSI ignores it for upgrades.
$version = if ([string]::IsNullOrWhiteSpace($PackageVersion)) { $sourceVersion } else { $PackageVersion }
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "PackageVersion must have exactly three numeric components." }
$parsedVersion = [version]$version
if ($parsedVersion.Major -gt 255 -or $parsedVersion.Minor -gt 255 -or $parsedVersion.Build -gt 65535) {
    throw "PackageVersion exceeds Windows Installer limits (255.255.65535)."
}
$jarName = "ahakey-studio-$sourceVersion.jar"
$jar = Join-Path $PSScriptRoot "target\$jarName"
$lib = Join-Path $PSScriptRoot "target\lib"
$bridge = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\BLE_tcp_bridge\bin\Release\BLE_tcp_driver.exe"))
$jpackage = Join-Path $JdkHome "bin\jpackage.exe"
foreach ($required in @($jar, $lib, $bridge, $jpackage, $RuntimeImage, $IconPath)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing build input: $required" }
}
& (Join-Path $PSScriptRoot "Test-ReleaseArtifactContents.ps1") -JarPath $jar
$modules = & (Join-Path $RuntimeImage "bin\java.exe") --list-modules
if ($LASTEXITCODE -ne 0 -or -not ($modules -match '^javafx.controls')) {
    throw "RuntimeImage must include JavaFX controls, graphics and FXML."
}

# New operation directory every time; do not delete earlier builds or installations.
$build = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) (Get-Date -Format "yyyyMMdd-HHmmss")
$inputDir = Join-Path $build "input"
$images = Join-Path $build "portable"
$installers = Join-Path $build "installer"
New-Item -ItemType Directory -Path $inputDir, $images, $installers -Force | Out-Null
Copy-Item -LiteralPath $jar -Destination $inputDir
Copy-Item -LiteralPath $lib -Destination (Join-Path $inputDir "lib") -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "..\LICENSE") -Destination (Join-Path $inputDir "LICENSE-AhaKey.txt")
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "..\docs\windows-korean.md") -Destination (Join-Path $inputDir "KOREAN-CHANGES.md")
New-Item -ItemType Directory -Path (Join-Path $inputDir "ble-driver") | Out-Null
Copy-Item -LiteralPath $bridge -Destination (Join-Path $inputDir "ble-driver\BLE_tcp_driver.exe")
if (Test-Path -LiteralPath "$bridge.config") {
    Copy-Item -LiteralPath "$bridge.config" -Destination (Join-Path $inputDir "ble-driver\BLE_tcp_driver.exe.config")
}
& (Join-Path $PSScriptRoot "Test-BleDriverPackaging.ps1") -ReleaseInputDir $inputDir

$arguments = @(
    "--type", "app-image", "--name", "AhaKeyStudio",
    "--app-version", $version, "--vendor", "AhaKey contributors (Korean community build)",
    "--description", "AhaKey Studio - Korean community build",
    "--input", $inputDir, "--main-jar", $jarName,
    "--main-class", "com.example.ahakey.App",
    "--runtime-image", ([IO.Path]::GetFullPath($RuntimeImage)),
    "--icon", ([IO.Path]::GetFullPath($IconPath)), "--dest", $images,
    "--java-options", "-Dfile.encoding=UTF-8",
    "--java-options", "-Dahakey.defaultLanguage=ko",
    "--java-options", "-Dapp.version=$version",
    "--java-options", "-Dprism.allowhidpi=true",
    "--java-options", "--add-opens=javafx.graphics/com.sun.javafx.application=ALL-UNNAMED",
    "--java-options", "--add-opens=javafx.controls/com.sun.javafx.scene.control=ALL-UNNAMED",
    "--java-options", "--add-opens=javafx.fxml/com.sun.javafx.fxml=ALL-UNNAMED"
)
& $jpackage @arguments
if ($LASTEXITCODE -ne 0) { throw "App-image build failed: $LASTEXITCODE" }
$image = Join-Path $images "AhaKeyStudio"
if (-not (Test-Path (Join-Path $image "AhaKeyStudio.exe"))) { throw "EXE missing" }
@"
AhaKey Studio $version — 한국어 커뮤니티 빌드

실행: AhaKeyStudio.exe. app 및 runtime 폴더를 실행 파일 옆에 유지하세요.
언어: 더 보기 → 언어 / Language → 한국어 선택 후 프로그램을 다시 시작하세요.
Java 및 BLE 브리지를 포함합니다. USB 연결에는 Bluetooth 동글이 필요하지 않습니다.
음성 입력은 별도 마이크가 필요합니다. 한국어 UI가 한국어 로컬 음성 인식을 추가하지는 않습니다.
음성 모델, 펌웨어, WCHISP는 포함하지 않습니다. 기기 펌웨어를 자동으로 변경하지 않습니다.
공식 한국어 배포판이 아닌 커뮤니티 수정본이며 게시자 디지털 서명은 없습니다.
소스·라이선스·변경 내역: https://github.com/gmkim-sds/desktop
"@ | Set-Content -LiteralPath (Join-Path $image "README-KO.txt") -Encoding UTF8
Compress-Archive -LiteralPath $image -DestinationPath (Join-Path $build "AhaKey-Studio-$version-KO-Portable.zip")

if (-not [string]::IsNullOrWhiteSpace($WixBin)) {
    foreach ($exe in @("candle.exe", "light.exe")) {
        if (-not (Test-Path (Join-Path $WixBin $exe))) { throw "WiX missing: $exe" }
    }
    $env:PATH = "$WixBin;$env:PATH"
    $resources = Join-Path $build "installer-resources"
    New-Item -ItemType Directory -Path $resources | Out-Null
    Copy-Item (Join-Path $PSScriptRoot "packaging\windows\*") -Destination $resources
    # Translate only the custom chooser in this local installer; retain the
    # repository's directory ownership and upgrade safeguards.
    $uiPath = Join-Path $resources "ui.wxf"
    $ui = [IO.File]::ReadAllText($uiPath)
    $labels = @{
        '[ProductName] 安装程序' = '[ProductName] 한국어 설치'
        '下一步(&amp;N)' = '다음'
        '上一步(&amp;B)' = '이전'
        '取消' = '취소'
        '选择父目录，安装程序会自动创建 AhaKeyStudio 文件夹。' = '선택한 폴더 안에 AhaKeyStudio 폴더를 만듭니다.'
        '选择安装位置' = '설치 위치'
        '请选择安装位置的父文件夹。实际安装目录将显示在下方。' = '설치할 상위 폴더를 선택하세요. 실제 설치 경로는 아래와 같습니다.'
        '程序文件夹：' = '프로그램 폴더: '
        '浏览父文件夹...' = '찾아보기…'
    }
    foreach ($label in ($labels.Keys | Sort-Object Length -Descending)) { $ui = $ui.Replace($label, $labels[$label]) }
    [IO.File]::WriteAllText($uiPath, $ui, [Text.UTF8Encoding]::new($false))
    $mainPath = Join-Path $resources "main.wxs"
    $mainXml = [IO.File]::ReadAllText($mainPath).Replace('<Product', '<Product Codepage="949"').Replace('JpProductLanguage=1033', 'JpProductLanguage=1042')
    [IO.File]::WriteAllText($mainPath, $mainXml, [Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "packaging\windows-ko\strings_ko.wxl") -Destination $resources
    $installerArgs = @(
        "--type", "exe", "--name", "AhaKeyStudio", "--app-version", $version,
        "--app-image", $image, "--dest", $installers,
        "--vendor", "AhaKey contributors (Korean community build)", "--install-dir", "AhaKeyStudio",
        "--resource-dir", $resources, "--win-dir-chooser", "--win-shortcut",
        "--win-menu", "--win-menu-group", "AhaKey",
        "--win-upgrade-uuid", "8842dbef-62f7-49ac-af0f-9447198265f3",
        "--temp", (Join-Path $build "jpackage-temp")
    )
    & $jpackage @installerArgs
    if ($LASTEXITCODE -ne 0) { throw "Installer build failed: $LASTEXITCODE" }
    $installer = Join-Path $installers "AhaKey-Studio-$version-KO-Setup.exe"
    Move-Item -LiteralPath (Join-Path $installers "AhaKeyStudio-$version.exe") -Destination $installer
    Write-Output "INSTALLER=$installer"
}
Write-Output "PORTABLE_EXE=$image\AhaKeyStudio.exe"
Write-Output "BUILD_DIRECTORY=$build"

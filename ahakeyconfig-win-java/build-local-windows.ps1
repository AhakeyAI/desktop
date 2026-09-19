param(
    [Parameter(Mandatory = $true)][string]$RuntimeImage,
    [Parameter(Mandatory = $true)][string]$IconPath,
    [string]$JdkHome = $env:JAVA_HOME,
    [string]$WixBin = "",
    [string]$OutputRoot = ""
)

# Local desktop build: no firmware, speech-model assets or vendor flasher are
# implied by this target. The formal release pipeline remains separate.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $PSScriptRoot "target\windows-ru"
}
[xml]$pom = Get-Content (Join-Path $PSScriptRoot "pom.xml") -Raw
$version = [string]$pom.project.version
$jarName = "ahakey-studio-$version.jar"
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
New-Item -ItemType Directory -Path (Join-Path $inputDir "ble-driver") | Out-Null
Copy-Item -LiteralPath $bridge -Destination (Join-Path $inputDir "ble-driver\BLE_tcp_driver.exe")
if (Test-Path -LiteralPath "$bridge.config") {
    Copy-Item -LiteralPath "$bridge.config" -Destination (Join-Path $inputDir "ble-driver\BLE_tcp_driver.exe.config")
}
& (Join-Path $PSScriptRoot "Test-BleDriverPackaging.ps1") -ReleaseInputDir $inputDir

$arguments = @(
    "--type", "app-image", "--name", "AhaKeyStudio",
    "--app-version", $version, "--vendor", "AhaKey",
    "--description", "AhaKey Studio - Russian interface",
    "--input", $inputDir, "--main-jar", $jarName,
    "--main-class", "com.example.ahakey.App",
    "--runtime-image", ([IO.Path]::GetFullPath($RuntimeImage)),
    "--icon", ([IO.Path]::GetFullPath($IconPath)), "--dest", $images,
    "--java-options", "-Dfile.encoding=UTF-8",
    "--java-options", "-Dahakey.defaultLanguage=ru",
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
AhaKey Studio $version — русский интерфейс

Запуск: AhaKeyStudio.exe. Сохраняйте папки app и runtime рядом с EXE.
Язык: Ещё → Язык / Language → Русский, затем перезапустите приложение.
Java и BLE-мост включены в комплект.
Модели локального распознавания речи, прошивка и WCHISP не включены.
Это локальная сборка без цифровой подписи издателя.
"@ | Set-Content -LiteralPath (Join-Path $image "ПРОЧИТАЙТЕ.txt") -Encoding UTF8
Compress-Archive -LiteralPath $image -DestinationPath (Join-Path $build "AhaKey-Studio-$version-RU-Portable.zip")

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
        '[ProductName] 安装程序' = 'Установка [ProductName]'
        '下一步(&amp;N)' = 'Далее'
        '上一步(&amp;B)' = 'Назад'
        '取消' = 'Отмена'
        '选择父目录，安装程序会自动创建 AhaKeyStudio 文件夹。' = 'В выбранной папке будет создана папка AhaKeyStudio.'
        '选择安装位置' = 'Папка установки'
        '请选择安装位置的父文件夹。实际安装目录将显示在下方。' = 'Выберите родительскую папку. Итоговый путь показан ниже.'
        '程序文件夹：' = 'Папка программы: '
        '浏览父文件夹...' = 'Обзор...'
    }
    foreach ($label in ($labels.Keys | Sort-Object Length -Descending)) { $ui = $ui.Replace($label, $labels[$label]) }
    [IO.File]::WriteAllText($uiPath, $ui, [Text.UTF8Encoding]::new($false))
    $mainPath = Join-Path $resources "main.wxs"
    $mainXml = [IO.File]::ReadAllText($mainPath).Replace('<Product', '<Product Codepage="1251"').Replace('JpProductLanguage=1033', 'JpProductLanguage=1049')
    [IO.File]::WriteAllText($mainPath, $mainXml, [Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "packaging\windows-ru\strings_ru.wxl") -Destination $resources
    $installerArgs = @(
        "--type", "exe", "--name", "AhaKeyStudio", "--app-version", $version,
        "--app-image", $image, "--dest", $installers,
        "--vendor", "AhaKey", "--install-dir", "AhaKeyStudio",
        "--resource-dir", $resources, "--win-dir-chooser", "--win-shortcut",
        "--win-menu", "--win-menu-group", "AhaKey",
        "--win-upgrade-uuid", "8842dbef-62f7-49ac-af0f-9447198265f3",
        "--temp", (Join-Path $build "jpackage-temp")
    )
    & $jpackage @installerArgs
    if ($LASTEXITCODE -ne 0) { throw "Installer build failed: $LASTEXITCODE" }
    $installer = Join-Path $installers "AhaKey-Studio-$version-RU-Setup.exe"
    Move-Item -LiteralPath (Join-Path $installers "AhaKeyStudio-$version.exe") -Destination $installer
    Write-Output "INSTALLER=$installer"
}
Write-Output "PORTABLE_EXE=$image\AhaKeyStudio.exe"
Write-Output "BUILD_DIRECTORY=$build"

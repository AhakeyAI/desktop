@echo off
setlocal enabledelayedexpansion

:: ============================================
:: AhaKey Studio 打包脚本
:: 依赖：JDK 17+, Maven 3.6+
:: ============================================

set "PROJECT_NAME=AhaKeyStudio"
set "VERSION=1.0.0"
set "MAIN_CLASS=com.example.ahakey.App"
set "TARGET_DIR=target"
set "INSTALLER_DIR=%TARGET_DIR%\installer"

echo ============================================
echo      AhaKey Studio 打包脚本
echo ============================================

:: 检查 Java
echo.
echo [1/5] 检查 Java 环境...
java -version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Java 未安装或未配置环境变量
    pause
    exit /b 1
)

for /f "tokens=3" %%g in ('java -version 2^>&1 ^| findstr /i "version"') do (
    set "JAVA_VERSION=%%g"
)
set "JAVA_VERSION=%JAVA_VERSION:"=%"
echo OK: Java 版本 %JAVA_VERSION%

:: 检查 Maven
echo.
echo [2/5] 检查 Maven 环境...
mvn -v >nul 2>&1
if errorlevel 1 (
    echo ERROR: Maven 未安装或未配置环境变量
    pause
    exit /b 1
)
echo OK: Maven 已安装

:: 编译项目
echo.
echo [3/5] 编译项目...
mvn clean package -DskipTests
if errorlevel 1 (
    echo ERROR: Maven 构建失败
    pause
    exit /b 1
)
echo OK: 编译成功

:: 检查 model.enabled 配置
set "MODEL_ENABLED=false"
for /f "tokens=1,* delims==" %%a in ('type src\main\resources\model_config.properties 2^>nul ^| findstr /i "model.enabled"') do (
    set "VAL=%%b"
    set "VAL=!VAL: =!"
    if /i "!VAL!"=="true" set "MODEL_ENABLED=true"
)
echo.
if /i "%MODEL_ENABLED%"=="true" (
    echo [INFO] model.enabled=true: 保留模型文件和 ONNX 运行时
) else (
    echo [INFO] model.enabled=false: 移除模型文件和 ONNX 运行时
    :: 删除 onnxruntime 依赖
    del /q "%TARGET_DIR%\lib\onnxruntime*.jar" 2>nul
    :: 从 JAR 中删除模型文件
    echo 正在从 JAR 中移除模型文件...
    pushd "%TARGET_DIR%"
    powershell -NoProfile -Command "$z=[System.IO.Compression.ZipFile]::Open('ahakey-studio-%VERSION%.jar','Update'); $z.Entries | Where-Object {$_.FullName -like 'models/*'} | ForEach-Object {$_.Delete()}; $z.Dispose()"
    popd
    echo OK: 已移除 onnxruntime 和模型文件 (~233MB)
)

:: 创建 Runtime Image
echo.
echo [4/5] 创建 Java Runtime Image...
set "JAR_PATH=%TARGET_DIR%\ahakey-studio-%VERSION%.jar"
set "LIB_DIR=%TARGET_DIR%\lib"
set "JLINK_DIR=%TARGET_DIR%\jlink-image"

:: 删除旧的 jlink 镜像
rd /s /q "%JLINK_DIR%" 2>nul

:: 使用 jdeps 分析依赖模块
echo 分析模块依赖...
for /f "skip=1" %%i in ('jdeps --list-deps "%JAR_PATH%"') do (
    set "MODULES=!MODULES!%%i,"
)
set "MODULES=%MODULES:~0,-1%"
echo 依赖模块: %MODULES%

:: 创建运行时镜像
jlink --module-path "%JAVA_HOME%\jmods" ^
      --add-modules %MODULES% ^
      --output "%JLINK_DIR%" ^
      --strip-debug ^
      --no-man-pages ^
      --no-header-files ^
      --compress=2

if errorlevel 1 (
    echo ERROR: jlink 失败
    pause
    exit /b 1
)
echo OK: Runtime Image 创建成功

:: 生成 EXE 安装程序
echo.
echo [5/5] 生成 EXE 安装程序...
rd /s /q "%INSTALLER_DIR%" 2>nul
mkdir "%INSTALLER_DIR%"

:: 准备 BLE 驱动文件
set "BLE_PROJECT_DIR=..\ahakeyconfig-win\BLE_tcp_bridge_for_vibe_code-master (1)\BLE_tcp_bridge_for_vibe_code-master"
set "BLE_EXE_SOURCE=%BLE_PROJECT_DIR%\dist\BLE_tcp_driver.exe"
set "BLE_STAGING=%TARGET_DIR%\ble_staging"
set "BLE_EXTRA_ARG="

if exist "%BLE_EXE_SOURCE%" (
    echo [INFO] 找到 BLE 驱动，准备打包...
    mkdir "%BLE_STAGING%" 2>nul
    copy /y "%BLE_EXE_SOURCE%" "%BLE_STAGING%\BLE_tcp_driver.exe" >nul
    set "BLE_EXTRA_ARG=--app-content "%BLE_STAGING%\BLE_tcp_driver.exe""
    echo OK: BLE 驱动已准备
) else (
    echo [WARNING] BLE 驱动未找到: %BLE_EXE_SOURCE%
    echo [WARNING] 请先在 BLE 项目中运行 build-single-exe.bat
)

jpackage --type exe ^
         --name %PROJECT_NAME% ^
         --app-version %VERSION% ^
         --vendor "AhaKey" ^
         --description "AhaKey Studio - 智能键盘配置工具" ^
         --copyright "2024 AhaKey. All rights reserved." ^
         --input "%TARGET_DIR%" ^
         --main-jar ahakey-studio-%VERSION%.jar ^
         --main-class %MAIN_CLASS% ^
         --runtime-image "%JLINK_DIR%" ^
         --dest "%INSTALLER_DIR%" ^
         --win-console false ^
         --win-dir-chooser ^
         --win-shortcut ^
         --win-menu ^
         --win-menu-group "AhaKey" ^
         --java-options "--add-opens=javafx.graphics/com.sun.javafx.application=ALL-UNNAMED" ^
         --java-options "--add-opens=javafx.controls/com.sun.javafx.scene.control=ALL-UNNAMED" ^
         --java-options "--add-opens=javafx.fxml/com.sun.javafx.fxml=ALL-UNNAMED" ^
         %BLE_EXTRA_ARG%

if errorlevel 1 (
    echo ERROR: jpackage 失败
    pause
    exit /b 1
)

echo.
echo ============================================
echo            打包完成！
echo ============================================
echo 安装包位置: %INSTALLER_DIR%\%PROJECT_NAME%-%VERSION%.exe
echo.
pause

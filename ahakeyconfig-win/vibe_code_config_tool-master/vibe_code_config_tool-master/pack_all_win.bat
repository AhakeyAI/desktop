@echo off
chcp 65001 >nul
setlocal EnableExtensions

set "PROJECT_DIR=%~dp0"
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
for %%I in ("%PROJECT_DIR%\..\..") do set "REPO_DIR=%%~fI"
set "DIST_DIR=%PROJECT_DIR%\dist"
set "WORK_ROOT=E:\VibecodingKeyboard_build"
set "PAYLOAD_DIR=%WORK_ROOT%\installer_payload"
set "OUTPUT_DIR=%WORK_ROOT%\output"
set "BACKUP_CAPSWRITER=%WORK_ROOT%\backup\Capswriter"
set "BACKUP_CAPSWRITER2=%WORK_ROOT%\backup\Capswriter_remaining2"
set "OLD_INSTALL_DIR=D:\Program Files\Vibecoding Keyboard"
set "CAPSWRITER_SRC=%REPO_DIR%\Capswriter-master\Capswriter-master"
rem Optional override for BLE driver location (absolute path to BLE_tcp_driver.exe)
rem Example: set BLE_DRIVER_EXE=C:\path\to\BLE_tcp_driver.exe
set "BLE_DRIVER_EXE=%BLE_DRIVER_EXE%"

cd /d "%PROJECT_DIR%" || exit /b 1

echo [1/5] Build KeyboardConfig.exe
call "%PROJECT_DIR%\pack_keyboard_win.bat" || exit /b 1

echo.
echo [2/5] Build hook_install.exe
set "AHAKEY_NO_PAUSE=1"
call "%PROJECT_DIR%\pack_hook_win.bat" || exit /b 1

echo.
echo [3/6] Build CapsWriter-Offline (exe)
if exist "%CAPSWRITER_SRC%\build.spec" (
  pushd "%CAPSWRITER_SRC%"
  rem Use absolute work/dist paths to avoid accidental nested build\build paths when CWD changes.
  set "CAPSWRITER_WORKPATH=%CAPSWRITER_SRC%\build_pyinstaller"
  set "CAPSWRITER_DISTPATH=%CAPSWRITER_SRC%\dist"
  if exist "%CAPSWRITER_WORKPATH%" rmdir /s /q "%CAPSWRITER_WORKPATH%"
  py -3 -c "0" >nul 2>&1
  if errorlevel 1 (
    python -c "0" >nul 2>&1 || (echo [ERROR] Python 3 not found for Capswriter build. & popd & exit /b 1)
    echo [pack] pip install capswriter deps ...
    python -m pip install -q -r requirements.txt pyinstaller || (popd & exit /b 1)
    echo [pack] PyInstaller build.spec ...
    python -m PyInstaller build.spec --noconfirm --workpath "%CAPSWRITER_WORKPATH%" --distpath "%CAPSWRITER_DISTPATH%" || (popd & exit /b 1)
  ) else (
    echo [pack] pip install capswriter deps ...
    py -3 -m pip install -q -r requirements.txt pyinstaller || (popd & exit /b 1)
    echo [pack] PyInstaller build.spec ...
    py -3 -m PyInstaller build.spec --noconfirm --workpath "%CAPSWRITER_WORKPATH%" --distpath "%CAPSWRITER_DISTPATH%" || (popd & exit /b 1)
  )
  popd
) else (
  echo [warn] Capswriter source not found at "%CAPSWRITER_SRC%". Will reuse existing runtime.
)

echo.
echo [4/6] Prepare installer payload on E: drive
if exist "%PAYLOAD_DIR%" rmdir /s /q "%PAYLOAD_DIR%"
mkdir "%PAYLOAD_DIR%" || exit /b 1

for /f "delims=" %%F in ('dir /b /a-d /o-d "%DIST_DIR%\Keyboard-win-*.exe" 2^>nul') do (
  copy /y "%DIST_DIR%\%%F" "%PAYLOAD_DIR%\KeyboardConfig.exe" >nul
  goto :keyboard_done
)
echo [ERROR] Missing Keyboard-win-*.exe in "%DIST_DIR%"
exit /b 1
:keyboard_done

if exist "%PROJECT_DIR%\hook\dist\Hook-install.exe" (
  copy /y "%PROJECT_DIR%\hook\dist\Hook-install.exe" "%PAYLOAD_DIR%\hook_install.exe" >nul
) else (
  echo [ERROR] Missing hook installer: "%PROJECT_DIR%\hook\dist\Hook-install.exe"
  exit /b 1
)

set "BLE_SOURCE="
if exist "%REPO_DIR%\BLE_tcp_bridge_for_vibe_code-master (1)\BLE_tcp_bridge_for_vibe_code-master\bin\Release\BLE_tcp_driver.exe" (
  set "BLE_SOURCE=%REPO_DIR%\BLE_tcp_bridge_for_vibe_code-master (1)\BLE_tcp_bridge_for_vibe_code-master\bin\Release\BLE_tcp_driver.exe"
)
if not defined BLE_SOURCE if exist "%REPO_DIR%\BLE_tcp_bridge_for_vibe_code-master (1)\BLE_tcp_bridge_for_vibe_code-master\bin\Debug\BLE_tcp_driver.exe" (
  set "BLE_SOURCE=%REPO_DIR%\BLE_tcp_bridge_for_vibe_code-master (1)\BLE_tcp_bridge_for_vibe_code-master\bin\Debug\BLE_tcp_driver.exe"
)
if not defined BLE_SOURCE if defined BLE_DRIVER_EXE if exist "%BLE_DRIVER_EXE%" (
  set "BLE_SOURCE=%BLE_DRIVER_EXE%"
)
if not defined BLE_SOURCE if exist "%DIST_DIR%\BLE_tcp_driver.exe" (
  set "BLE_SOURCE=%DIST_DIR%\BLE_tcp_driver.exe"
)
if not defined BLE_SOURCE if exist "%OLD_INSTALL_DIR%\BLE_tcp_driver.exe" (
  set "BLE_SOURCE=%OLD_INSTALL_DIR%\BLE_tcp_driver.exe"
)

if not defined BLE_SOURCE (
  echo [ERROR] Missing BLE_tcp_driver.exe. Build BLE driver first or keep old install at "%OLD_INSTALL_DIR%".
  echo         Fix options:
  echo         - Put BLE_tcp_driver.exe at "%DIST_DIR%\BLE_tcp_driver.exe"
  echo         - Or set BLE_DRIVER_EXE to the full path of BLE_tcp_driver.exe
  exit /b 1
)

echo [pack] Using BLE driver: "%BLE_SOURCE%"
copy /y "%BLE_SOURCE%" "%PAYLOAD_DIR%\BLE_tcp_driver.exe" >nul || (
  echo [ERROR] Failed to copy BLE driver from "%BLE_SOURCE%"
  exit /b 1
)
if not exist "%PAYLOAD_DIR%\BLE_tcp_driver.exe" (
  echo [ERROR] BLE driver copy verification failed: "%PAYLOAD_DIR%\BLE_tcp_driver.exe"
  exit /b 1
)

rem Prefer packaged CapsWriter-Offline exes so target machines don't need Python.
if exist "%CAPSWRITER_SRC%\dist\CapsWriter-Offline\start_server.exe" (
  echo [pack] Using CapsWriter-Offline exes from "%CAPSWRITER_SRC%\dist\CapsWriter-Offline"
  robocopy "%CAPSWRITER_SRC%\dist\CapsWriter-Offline" "%PAYLOAD_DIR%\Capswriter\dist\CapsWriter-Offline" /E /XD logs __pycache__ /XF *.pyc >nul
  if errorlevel 8 exit /b 1
  if exist "%CAPSWRITER_SRC%\models" (
    robocopy "%CAPSWRITER_SRC%\models" "%PAYLOAD_DIR%\Capswriter\dist\CapsWriter-Offline\models" /E /XD logs __pycache__ /XF *.pyc >nul
    if errorlevel 8 exit /b 1
  )
) else if exist "%DIST_DIR%\Capswriter" (
  echo [warn] Falling back to Capswriter source runtime from "%DIST_DIR%\Capswriter"
  robocopy "%DIST_DIR%\Capswriter" "%PAYLOAD_DIR%\Capswriter" /E /XD logs __pycache__ /XF *.pyc >nul
  if errorlevel 8 exit /b 1
) else if exist "%BACKUP_CAPSWRITER%" (
  echo [warn] Reusing Capswriter from "%BACKUP_CAPSWRITER%"
  robocopy "%BACKUP_CAPSWRITER%" "%PAYLOAD_DIR%\Capswriter" /E /XD logs __pycache__ /XF *.pyc >nul
  if errorlevel 8 exit /b 1
) else if exist "%BACKUP_CAPSWRITER2%" (
  echo [warn] Reusing Capswriter from "%BACKUP_CAPSWRITER2%"
  robocopy "%BACKUP_CAPSWRITER2%" "%PAYLOAD_DIR%\Capswriter" /E /XD logs __pycache__ /XF *.pyc >nul
  if errorlevel 8 exit /b 1
) else if exist "%OLD_INSTALL_DIR%\Capswriter" (
  echo [warn] Reusing Capswriter from "%OLD_INSTALL_DIR%"
  robocopy "%OLD_INSTALL_DIR%\Capswriter" "%PAYLOAD_DIR%\Capswriter" /E /XD logs __pycache__ /XF *.pyc >nul
  if errorlevel 8 exit /b 1
) else (
  echo [ERROR] Missing Capswriter runtime.
  exit /b 1
)

for %%F in (config.json config_client.json config_server.json VC_redist.x64.exe) do (
  if exist "%OLD_INSTALL_DIR%\%%F" copy /y "%OLD_INSTALL_DIR%\%%F" "%PAYLOAD_DIR%\%%F" >nul
)

echo.
echo [5/6] Locate Inno Setup compiler
set "ISCC="
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not defined ISCC if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if not defined ISCC if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if not defined ISCC for /f "delims=" %%I in ('where ISCC.exe 2^>nul') do if not defined ISCC set "ISCC=%%I"
if not defined ISCC (
  echo [warn] Inno Setup 6 not found. Trying winget install ...
  where winget.exe >nul 2>&1
  if not errorlevel 1 (
    winget install --id JRSoftware.InnoSetup -e --accept-package-agreements --accept-source-agreements
    if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
    if not defined ISCC if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
    if not defined ISCC if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
  )
)
if not defined ISCC (
  echo [ERROR] Inno Setup 6 not found. Install it, then rerun this script.
  echo         Download: https://jrsoftware.org/isdl.php
  exit /b 1
)

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%" || exit /b 1

echo.
echo [6/6] Build setup exe
"%ISCC%" ^
  /DSourceRoot="%PAYLOAD_DIR%" ^
  /DOutputDir="%OUTPUT_DIR%" ^
  /DSetupIcon="%PROJECT_DIR%\ico\VibeCodeKeyboard.ico" ^
  "%PROJECT_DIR%\VibecodingKeyboard_Setup.iss" || exit /b 1

echo.
echo [OK] Installer created:
echo      "%OUTPUT_DIR%\VibecodingKeyboard_Setup.exe"
echo.
echo Payload preview:
dir /b "%PAYLOAD_DIR%"
endlocal
exit /b 0

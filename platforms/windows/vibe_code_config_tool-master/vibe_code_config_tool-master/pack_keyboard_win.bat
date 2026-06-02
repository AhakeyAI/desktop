@echo off
chcp 65001 >nul
setlocal EnableExtensions
cd /d "%~dp0" || exit /b 1

for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMddHHmmss"`) do set "TS=%%i"
set "AHAKEY_KEYBOARD_EXE_NAME=Keyboard-win-%TS%"

set "PY=py -3"
%PY% -c "0" >nul 2>&1 || set "PY=python"
%PY% -c "0" >nul 2>&1 || (
  echo [ERROR] 未找到 Python，请安装 Python 3 或使用 py 启动器。
  exit /b 1
)

echo [pack] pip install ...
%PY% -m pip install -q -r requirements.txt pyinstaller || exit /b 1

echo [pack] 主程序单文件 exe：%AHAKEY_KEYBOARD_EXE_NAME%.exe
%PY% -m PyInstaller KeyboardConfig-onefile.spec --noconfirm || exit /b 1

echo.
echo [OK] "%cd%\dist\%AHAKEY_KEYBOARD_EXE_NAME%.exe"
endlocal

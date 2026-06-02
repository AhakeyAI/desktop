@echo off
chcp 65001 >nul
setlocal EnableExtensions
cd /d "%~dp0%" || (echo 切换目录失败 & pause >nul & exit /b 1)

for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMddHHmmss"`) do set "TS=%%i"
set "AHAKEY_HOOK_EXE_NAME=Hook-win-%TS%"

set "PY=py -3"
%PY% -c "0" >nul 2>&1 || set "PY=python"
%PY% -c "0" >nul 2>&1 || (
    echo [ERROR] 未找到 Python，请安装 Python 3 并配置环境变量
    pause
    exit /b 1
)

echo [pack] 安装依赖包...
%PY% -m pip install -q -r requirements.txt pyinstaller

echo [pack] 开始打包 Hook 单文件 exe：%AHAKEY_HOOK_EXE_NAME%.exe

:: 关键修复：直接进入 hook 目录，再执行打包（保证 launcher.py 路径正确）
cd /d "%~dp0%\hook"

%PY% -m PyInstaller launcher.py --onefile --noconfirm
set "ERR=%ERRORLEVEL%"

echo.
if "%ERR%"=="0" (
    echo [OK] 打包成功！
    echo 输出文件：%cd%\dist\launcher.exe
    echo 已重命名为：%AHAKEY_HOOK_EXE_NAME%.exe
    if exist "%cd%\dist\launcher.exe" (
        ren "%cd%\dist\launcher.exe" "%AHAKEY_HOOK_EXE_NAME%.exe"
    )
    if exist "%cd%\dist\%AHAKEY_HOOK_EXE_NAME%.exe" (
        copy /Y "%cd%\dist\%AHAKEY_HOOK_EXE_NAME%.exe" "%cd%\dist\Hook-install.exe" >nul
        echo [OK] 固定入口（供 Codex/Cursor 配置引用，路径不变）：%cd%\dist\Hook-install.exe
        echo      请先运行 Hook-install.exe，再点「安装 Codex Hooks」或「安装 Cursor Hooks」写入 config。
        echo      （带时间戳的 %AHAKEY_HOOK_EXE_NAME%.exe 可作版本留档）
    )
) else (
    echo [ERROR] 打包失败，错误码：%ERR%
)

echo.
echo 【打包结束，请查看上方日志】
pause
endlocal
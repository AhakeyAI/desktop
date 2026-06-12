@echo off
chcp 65001 >nul
cd /d "%~dp0%"

echo ==============================================
echo 正在打包 KeyboardConfig...
echo ==============================================

python -m PyInstaller KeyboardConfig.spec --noconfirm

echo.
echo ✅ 打包成功！
echo 输出文件夹： dist\KeyboardConfig\
echo 启动文件：   dist\KeyboardConfig\KeyboardConfig.exe
echo.

pause
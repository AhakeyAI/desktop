@echo off
chcp 65001 >nul
cd /d "%~dp0" || exit /b 1
call "%~dp0pack_keyboard_win.bat" || exit /b 1
call "%~dp0pack_hook_win.bat" || exit /b 1
echo.
echo [OK] 主程序与 Hook 安装器均已打包完成。
exit /b 0

# -*- mode: python ; coding: utf-8 -*-
# Hook 安装器单文件 exe，名称由环境变量 AHAKEY_HOOK_EXE_NAME 决定（默认 Hook-win-local）
# 配合 pack_hook_win.bat 使用；请在 hook 目录下执行 PyInstaller

import os

try:
    _hook_dir = os.path.dirname(os.path.abspath(SPECPATH))
except NameError:
    _hook_dir = os.getcwd()

EXE_NAME = os.environ.get("AHAKEY_HOOK_EXE_NAME", "Hook-win-local")

a = Analysis(
    [os.path.join(_hook_dir, "launcher.py")],
    pathex=[_hook_dir],
    binaries=[],
    datas=[],
    hiddenimports=[
        "hook_install",
        "hook_diag",
        "SessionStart",
        "SessionEnd",
        "PreToolUse",
        "PostToolUse",
        "PermissionRequest",
        "Notification",
        "TaskCompleted",
        "Stop",
        "UserPromptSubmit",
        "codex_hooks",
        "ble_command_send",
        "UdpLog",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name=EXE_NAME,
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

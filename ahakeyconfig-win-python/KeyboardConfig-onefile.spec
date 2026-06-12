# -*- mode: python ; coding: utf-8 -*-
# 单文件 exe，名称由环境变量 AHAKEY_KEYBOARD_EXE_NAME 决定（默认 Keyboard-win-local）
# 配合 pack_keyboard_win.bat 使用

import os

block_cipher = None

try:
    _spec_dir = os.path.dirname(os.path.abspath(SPECPATH))
except NameError:  # 极少数环境下无 SPECPATH 时退化为当前目录
    _spec_dir = os.getcwd()

EXE_NAME = os.environ.get("AHAKEY_KEYBOARD_EXE_NAME", "Keyboard-win-local")

_icon = os.path.join(_spec_dir, "ico", "VibeCodeKeyboard.ico")
_icon_arg = _icon if os.path.isfile(_icon) else None

a = Analysis(
    [os.path.join(_spec_dir, "main.py")],
    pathex=[_spec_dir],
    binaries=[],
    datas=[],
    hiddenimports=[
        "PySide6.QtCore",
        "PySide6.QtGui",
        "PySide6.QtWidgets",
        "PIL",
        "PIL.Image",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        "matplotlib",
        "pandas",
        "cv2",
        "PyQt5",
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

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
    upx=False,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=_icon_arg,
)

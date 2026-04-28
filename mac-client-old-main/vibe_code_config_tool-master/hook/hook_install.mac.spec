# -*- mode: python ; coding: utf-8 -*-

from pathlib import Path

icon_file = Path('..') / 'ico' / 'VibeCodeKeyboard.ico'
datas = []
if icon_file.is_file():
    datas.append((str(icon_file), 'ico'))

a = Analysis(
    ['launcher.py'],
    pathex=['.'],
    binaries=[],
    datas=datas,
    hiddenimports=[
        'hook_install',
        'hook_manager_qt',
        'SessionStart',
        'SessionEnd',
        'PreToolUse',
        'PostToolUse',
        'PermissionRequest',
        'Notification',
        'TaskCompleted',
        'Stop',
        'UserPromptSubmit',
        'ble_command_send',
        'UdpLog',
        'PySide6.QtCore',
        'PySide6.QtGui',
        'PySide6.QtWidgets',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='hook_install',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    name='hook_install',
)

app = BUNDLE(
    coll,
    name='hook_install.app',
    icon=None,
    bundle_identifier='com.vibekeyboard.hookinstall',
    info_plist={
        'CFBundleDisplayName': 'Claude Cursor Hook Manager',
        'CFBundleName': 'hook_install',
    },
)

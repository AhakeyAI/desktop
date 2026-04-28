# -*- mode: python ; coding: utf-8 -*-

import os
import runpy
from pathlib import Path

from PyInstaller.utils.hooks import collect_submodules

project_dir = Path(globals().get("SPECPATH") or Path.cwd()).resolve()
default_app_version = str(
    runpy.run_path(str(project_dir / "src" / "core" / "app_version.py")).get("APP_VERSION", "0.1.0")
).strip() or "0.1.0"
app_version = os.environ.get("APP_VERSION", default_app_version).strip() or default_app_version
icon_file = project_dir / "assets" / "macos" / "VibeCodeKeyboard.icns"
app_icon = str(icon_file) if icon_file.is_file() else None

app_hiddenimports = [
    'src.core.hook_runtime',
    'src.core.voice_runtime',
    'AVFoundation',
    'AppKit',
    'Quartz',
    'uuid',
    'logging.handlers',
    'websockets',
    'sounddevice',
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
]

a = Analysis(
    ['main.py'],
    pathex=[str(project_dir), str(project_dir / 'hook')],
    binaries=[],
    datas=[],
    hiddenimports=[
        'PySide6.QtCore',
        'PySide6.QtGui',
        'PySide6.QtWidgets',
        'PIL',
        'PIL.Image',
        *app_hiddenimports,
        *collect_submodules('websockets'),
        *collect_submodules('PIL'),
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        'matplotlib',
        'pandas',
        'cv2',
        'PyQt5',
    ],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='KeyboardConfig',
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
    a.datas,
    strip=False,
    upx=False,
    name='KeyboardConfig',
)

app = BUNDLE(
    coll,
    name='Vibecoding Keyboard.app',
    icon=app_icon,
    bundle_identifier='com.vibekeyboard.keyboardconfig',
    info_plist={
        'CFBundleDisplayName': 'Vibecoding Keyboard',
        'CFBundleName': 'Vibecoding Keyboard',
        'CFBundleShortVersionString': app_version,
        'CFBundleVersion': app_version,
        'NSBluetoothAlwaysUsageDescription': 'Connect to the Vibe Keyboard over Bluetooth.',
        'NSMicrophoneUsageDescription': 'Use the microphone for voice input.',
    },
)

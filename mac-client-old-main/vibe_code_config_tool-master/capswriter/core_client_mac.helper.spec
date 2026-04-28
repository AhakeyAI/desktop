# -*- mode: python ; coding: utf-8 -*-

from pathlib import Path

from PyInstaller.utils.hooks import collect_data_files, collect_submodules

project_dir = Path(globals().get("SPECPATH") or Path.cwd()).resolve()

datas = []
for name in ("focused_text_injector.swift", "focused_text_injector"):
    path = project_dir / name
    if path.exists():
        datas.append((str(path), "."))
for name in ("voice_hud.py",):
    path = project_dir / name
    if path.exists():
        datas.append((str(path), "."))
datas.extend(collect_data_files("pypinyin"))
datas.extend(collect_data_files("certifi"))

a = Analysis(
    ["core_client_mac.py"],
    pathex=[str(project_dir)],
    binaries=[],
    datas=datas,
    hiddenimports=[
        "numpy",
        "sounddevice",
        "websockets",
        "Quartz",
        "AppKit",
        "AVFoundation",
        "objc",
        "requests",
        "pypinyin",
        "watchdog",
        "watchdog.events",
        "watchdog.observers",
        *collect_submodules("websockets"),
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        "PySide6",
        "qdarktheme",
        "matplotlib",
        "pandas",
        "cv2",
        "PyQt5",
    ],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="core_client_mac",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    contents_directory="core_client_mac_internal",
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
    name="core_client_mac",
)

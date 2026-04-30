# -*- mode: python ; coding: utf-8 -*-

from pathlib import Path

from PyInstaller.utils.hooks import collect_data_files, collect_dynamic_libs, collect_submodules

project_dir = Path(globals().get("SPECPATH") or Path.cwd()).resolve()

datas = []
datas.extend(collect_data_files("sherpa_onnx"))
datas.extend(collect_data_files("pypinyin"))
datas.extend(collect_data_files("certifi"))

binaries = []
binaries.extend(collect_dynamic_libs("sherpa_onnx"))

a = Analysis(
    ["core_server.py"],
    pathex=[str(project_dir)],
    binaries=binaries,
    datas=datas,
    hiddenimports=[
        "websockets",
        "typer",
        "colorama",
        "rich",
        "rich.console",
        "rich.markdown",
        "requests",
        "sherpa_onnx",
        "pypinyin",
        "logging.handlers",
        "queue",
        "concurrent.futures.thread",
        "multiprocessing.managers",
        *collect_submodules("websockets"),
        *collect_submodules("sherpa_onnx"),
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
    name="core_server",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    contents_directory="core_server_internal",
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
    name="core_server",
)

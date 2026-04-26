# Install on Windows

This guide is for newcomers who want to install or run the Windows version of AhaKey.

## Recommended: install from GitHub Releases

1. Open the `AhakeyAI/desktop` **Releases** page.
2. Download the latest Windows installer asset (`.exe` or `.msi`).
3. Run the installer and follow the setup wizard.
4. Launch AhaKey from the Start Menu after installation.

> Note: this repository is source-only. Installer binaries are distributed via GitHub Releases, not committed in the repo.

## For contributors: run Windows modules from source

There is currently no single one-click Windows build entry. Build/run by module:

### 1) desktop-main

- Path: `platforms/windows/desktop-main/vibe_code_config_tool/`
- Typical dev start:
  - `pip install -r requirements.txt`
  - `python main.py`

### 2) ble-bridge

- Path: `platforms/windows/ble-bridge/BLE_tcp_bridge_for_vibe_code/`
- Typical build:
  - Open `BLE_tcp_driver.sln` in Visual Studio and build
  - Or build `BLE_tcp_driver.csproj` with .NET Framework 4.7.2 toolchain

### 3) hook-installer

- Path: `platforms/windows/hook-installer/vibe_code_hook/`
- Common entry scripts:
  - `python hook_install.py`
  - `python install_hook.py`
  - `python install_cursor_hook.py`

### 4) speech

- Path: `platforms/windows/speech/Capswriter/`
- Typical dev start:
  - `pip install -r requirements.txt`
  - `python start_server.py`
  - `python start_client.py`

## Scope and expectations

- This repo does **not** include release artifacts like `exe` / `msi`.
- Historical packaging scripts (for example under `platforms/windows/scripts/inno-setup/`) are retained for migration reference and may not be directly reusable as current release pipelines.

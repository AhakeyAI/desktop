# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A cross-platform PySide6 (Qt) configuration tool for a 4-key BLE keyboard with a 160x80 display. The keyboard has **3 work modes**, each with independent key mappings (4 keys) and display animations. Communication goes through a TCP-to-BLE bridge.

## Commands

```bash
# Run the application
python main.py

# Install dependencies
pip install -r requirements.txt

# Legacy test tools (for protocol debugging)
python test_ble_tcp_bridge_client.py   # Tkinter debug client
python send_pic_array_test.py          # Image upload test script
```

## Architecture

Three-layer design with strict dependency direction: **UI → Core → Comm**

- **`src/comm/`** — TCP socket communication and device protocol
  - `protocol.py`: Packet/frame constants, builders, parsers (no state)
  - `tcp_client.py`: Socket I/O with background receive thread, emits `packet_received` signal
  - `device_service.py`: High-level device commands (synchronous command/response with `threading.Lock` + `threading.Event`)

- **`src/core/`** — Business logic and data models (no GUI imports except `QObject` for signals)
  - `device_state.py`: **Central state hub** — all UI components connect to its signals; owns `TcpClient` and `DeviceService` instances
  - `keymap.py`: Data model hierarchy: `KeyboardConfig` → `ModeConfig` (×3) → `KeyBinding` (×4) + `DisplayMode`
  - `keycodes.py`: HID keycode database with lookup tables by name, code, and category
  - `image_processor.py`: PIL-based image resize + RGB565 big-endian encoding (replaces legacy OpenCV code)
  - `config_manager.py`: JSON serialization/deserialization of `KeyboardConfig`

- **`src/ui/`** — PySide6 widgets and pages
  - `main_window.py`: Orchestrates everything — menu bar, tab navigation, signal wiring
  - `pages/mode_page.py`: Core config page (keymap editor + animation manager per mode), contains `UploadWorker` QThread
  - `pages/device_page.py`: Device info display + communication log
  - `widgets/`: Reusable components (connection_bar, keyboard_view, key_editor, mode_selector, image_preview)

## Key Patterns

**Signal flow**: `TcpClient` (background thread) → `DeviceService` → `DeviceState` → UI widgets. All cross-thread communication uses Qt signals (auto-queued).

**Command/Response**: `DeviceService.send_command()` acquires a lock, sends a frame, then blocks on `threading.Event.wait()` for the matching response. Large uploads use `write_large_data()` which chunks data into 4KB blocks with PREPARE_WRITE/WRITE_DATA handshake per chunk.

**QObject.connect name conflict**: `TcpClient` and `DeviceState` avoid naming methods `connect()`/`disconnect()` since they inherit `QObject`. Use `open()`/`disconnect()` and `connect_device()`/`disconnect_device()` respectively.

## Protocol

TCP packet: `[Type:1][Length:2 LE][Data:N]`. Device frame: `[0xAABB][Cmd:1][Data:N][0xCCDD]`.

Key types: `PKT_WRITE_CMD(0x02)` for commands, `PKT_WRITE_DATA(0x01)` for raw data, `PKT_BLE_NOTIFY(0x81)` for responses, `PKT_QUERY_STATUS(0x03)`/`PKT_QUERY_INFO(0x04)` for bridge queries.

Device commands: `SAVE_CONFIG(0x04)`, `PREPARE_WRITE(0x80)`, `WRITE_RESULT(0x81)`, `UPDATE_PIC(0x82)`.

## Display Constants

- Resolution: 160×80 pixels, RGB565 big-endian (25,600 bytes/frame)
- Frame slot: 28,672 bytes (7 × 4KB), addresses must be 4K-aligned
- Max 74 frames total across all 3 modes
- Frames are uploaded sequentially: mode0 frames first, then mode1, then mode2

## Hooks (Claude / Cursor)

IDE hooks 使用 **单入口 + 事件名分发**：无论 Claude 还是 Cursor，都通过 `hook/hook_install.py` 安装与执行。

- **推荐安装方式**：运行 `python hook/hook_install.py` 打开 UI，或 `python hook/hook_install.py --install-cursor` / `--uninstall-cursor` 仅操作 Cursor。根目录的 `install_hook.py`（Claude）和 `install_cursor_hook.py`（委托给 hook_install）仅作备用。
- **执行路径**：Claude/Cursor 触发时执行的是 `hook_install.py <事件名>`，由 hook_install 内部分发到 `SessionStart.run()` 等；各 `hook/*.py` 的 `if __name__ == "__main__": run()` 保留便于单脚本测试。

## Python Version Note

Target is Python 3.9+. Avoid `X | Y` union type syntax (use `Optional[X]` from typing). `list[str]`, `dict[str, int]` lowercase generics are fine (PEP 585).

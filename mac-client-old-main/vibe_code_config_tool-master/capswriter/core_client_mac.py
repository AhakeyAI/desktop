# coding: utf-8
"""
CapsWriter macOS 客户端 — 独立语音触发键方案

原理：
  CapsLock 完全交给 macOS 原生处理，避免和大小写 / 输入法切换冲突。
  语音输入只监听独立触发键 F18：

  短按 CapsLock → 完全交给系统原生处理
  长按 Voice Trigger (F18) → 开始录音
  松开 Voice Trigger (F18) → 停止录音 → 识别 → 粘贴到光标

依赖：
    pip install pyobjc-framework-Quartz
    pip install sounddevice numpy websockets

用法：
    python core_client_mac.py
"""

from __future__ import annotations

import asyncio
import atexit
import base64
import json
import os
import re
import subprocess
import sys
import time
import uuid
import wave
from pathlib import Path
from threading import Thread


def _boot_debug(message: str) -> None:
    if os.environ.get("VIBE_DEBUG_CLIENT_BOOT", "").strip() != "1":
        return
    try:
        with open("/tmp/vibecoding_client_boot.log", "a", encoding="utf-8") as f:
            f.write(f"{time.strftime('%H:%M:%S')} {message}\n")
    except Exception:
        pass


_boot_debug("bootstrap: start imports")

# ── 清除代理设置，避免 localhost 连接走 SOCKS 代理 ──
for _proxy_var in list(os.environ.keys()):
    if "proxy" in _proxy_var.lower():
        del os.environ[_proxy_var]

_boot_debug("bootstrap: before numpy")
import numpy as np
_boot_debug("bootstrap: after numpy")
_boot_debug("bootstrap: before sounddevice")
import sounddevice as sd
_boot_debug("bootstrap: after sounddevice")
_boot_debug("bootstrap: before websockets")
import websockets
_boot_debug("bootstrap: after websockets")

# 在打包版的独立 Python runtime 里，直接在进程启动阶段 import
# AVFoundation 有概率卡死，用户看起来就像“一点启动语音输入就挂住”。
# 这里不再在模块导入时碰它，麦克风权限改成通过隔离子进程探测/触发。

# ── 录音提示音 ──
try:
    from audio_cue import (
        play_start_cue,
        play_stop_cue,
        is_enabled as _audio_cue_is_enabled,
        _check_config as _refresh_audio_cue_config,
    )
except ImportError:
    def play_start_cue(): pass
    def play_stop_cue(): pass
    def _audio_cue_is_enabled() -> bool: return False
    def _refresh_audio_cue_config() -> None: pass

# ── AI 文本优化 ──
try:
    from text_optimizer import optimize_text
except ImportError:
    def optimize_text(text: str, app_name: str = "") -> str: return text

# ── 纠错自动学习 ──
try:
    from correction_learner import schedule_learning
except ImportError:
    def schedule_learning(text: str): pass

try:
    from correction_learner import read_focused_text
except ImportError:
    def read_focused_text() -> str: return ""


def _get_frontmost_app() -> str:
    """避免触发 System Events 自动化授权；前台应用优先走 NSWorkspace。"""
    return ""

# 这台老机器上的打包版在导入 AppKit/Quartz（PyObjC 桥）时会卡死。
# 事件监听、鼠标回放、Cmd+V 和 Unicode 直输统一改走 Swift helper，
# Python 端只保留录音、WebSocket 和状态机。

# ── 配置 ──────────────────────────────────────────────
SERVER_PORT = 6016
TARGET_SAMPLE_RATE = 16000
BLOCK_DURATION = 0.05          # 50 ms
THRESHOLD = 0.1                # 录音数据缓冲阈值（秒）
SEG_DURATION = 60
SEG_OVERLAP = 4
TRASH_PUNC = "，。,."           # 去掉末尾标点
V_KEYCODE = 9                  # macOS virtual keycode for V
VOICE_TRIGGER_KEYCODE = 79     # macOS virtual keycode for F18
VOICE_TRIGGER_LABEL = "Voice Trigger (F18)"
VOICE_TRIGGER_LONG_PRESS_SECONDS = 0.28
# ──────────────────────────────────────────────────────

# 全局状态
_loop: asyncio.AbstractEventLoop = None
_queue: asyncio.Queue = None
_ws = None
_recording = False
_record_start = 0.0
_task_id: str = ""
_record_pointer_point = None
_frontmost_app_hint: str = ""
_frontmost_app_hint_at = 0.0
_frontmost_app_bundle_id: str = ""
_frontmost_app_pid: int = 0
_last_external_app_hint: str = ""
_last_external_app_hint_at = 0.0
_last_external_app_bundle_id: str = ""
_last_external_app_pid: int = 0
_hud_proc: subprocess.Popen | None = None
_voice_input_bridge_proc: subprocess.Popen | None = None
_text_injector_ready = False
_text_injector_checked = False
_voice_input_bridge_ready = False
_voice_input_bridge_checked = False
_capture_sample_rate = TARGET_SAMPLE_RATE
_capture_channels = 1
_capture_device_name = ""
_capslock_is_remapped = False
_voice_trigger_pressed = False
_voice_trigger_started_at = 0.0
_voice_trigger_token = 0
_last_pointer_point: tuple[float, float] | None = None
_channel_selection_logged = False
_record_audio_gate_until = 0.0
_record_debug_dump_index = 0

_HUD_READY_TIMEOUT_MS = 1400
_HUD_PASTE_TIMEOUT_MS = 1200
_HUD_ERROR_TIMEOUT_MS = 2600
_START_CUE_GATE_SECONDS = 0.08


def _voice_hud_enabled() -> bool:
    flag = os.environ.get("CAPSWRITER_ENABLE_HUD", "").strip().lower()
    if flag in {"1", "true", "yes", "on"}:
        return True
    if flag in {"0", "false", "no", "off"}:
        return False
    return True


def _should_refocus_record_pointer() -> bool:
    flag = os.environ.get("CAPSWRITER_CLICK_REFOCUS", "").strip().lower()
    if flag in {"0", "false", "no", "off"}:
        return False
    if flag in {"1", "true", "yes", "on"}:
        return True
    return True


def _voice_hud_script() -> Path:
    env_home = os.environ.get("CAPSWRITER_HOME", "").strip()
    if env_home:
        candidate = Path(env_home).expanduser() / "voice_hud.py"
        if candidate.is_file():
            return candidate.resolve()
    return Path(__file__).resolve().with_name("voice_hud.py")


def _voice_hud_python() -> str:
    env_home = os.environ.get("CAPSWRITER_HOME", "").strip()
    if env_home:
        runtime_python = (
            Path(env_home).expanduser()
            / ".python-runtime"
            / "Python.framework"
            / "Versions"
            / f"{sys.version_info.major}.{sys.version_info.minor}"
            / "bin"
            / "python3"
        )
        if runtime_python.is_file():
            return str(runtime_python.resolve())

    python_home = os.environ.get("PYTHONHOME", "").strip()
    if python_home:
        candidate = Path(python_home).expanduser() / "bin" / "python3"
        if candidate.is_file():
            return str(candidate.resolve())

    return sys.executable


def _voice_hud_command() -> list[str]:
    bootstrap_exe = os.environ.get("CAPSWRITER_BOOTSTRAP_EXE", "").strip()
    env_home = os.environ.get("CAPSWRITER_HOME", "").strip()
    if bootstrap_exe and Path(bootstrap_exe).is_file():
        command = [bootstrap_exe, "--capswriter-bootstrap", "voice_hud"]
        if env_home:
            command.extend(["--capswriter-home", env_home])
        return command

    script = _voice_hud_script()
    return [_voice_hud_python(), "-u", str(script)]


def _text_injector_source() -> Path:
    env_home = os.environ.get("CAPSWRITER_HOME", "").strip()
    if env_home:
        candidate = Path(env_home).expanduser() / "focused_text_injector.swift"
        if candidate.is_file():
            return candidate.resolve()
    return Path(__file__).resolve().with_name("focused_text_injector.swift")


def _text_injector_binary() -> Path:
    env_home = os.environ.get("CAPSWRITER_HOME", "").strip()
    if env_home:
        candidate = Path(env_home).expanduser() / "focused_text_injector"
        if candidate.is_file():
            return candidate.resolve()
    return Path(__file__).resolve().with_name("focused_text_injector")


def _ensure_text_injector_ready() -> bool:
    global _text_injector_ready, _text_injector_checked
    if _text_injector_ready:
        return True
    if _text_injector_checked and not _text_injector_ready:
        return False

    _text_injector_checked = True
    source = _text_injector_source()
    binary = _text_injector_binary()
    if not source.is_file():
        return False

    try:
        needs_build = (not binary.is_file()) or (source.stat().st_mtime > binary.stat().st_mtime)
    except Exception:
        needs_build = True

    try:
        if needs_build:
            subprocess.run(
                ["swiftc", "-O", str(source), "-o", str(binary)],
                timeout=40,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True,
            )
        _text_injector_ready = binary.is_file()
    except Exception as e:
        print(f"[AX] Swift 文本注入器不可用: {e}", flush=True)
        _text_injector_ready = False

    return _text_injector_ready


def _warmup_text_injector() -> None:
    _ensure_text_injector_ready()


def _voice_input_bridge_source() -> Path:
    env_home = os.environ.get("CAPSWRITER_HOME", "").strip()
    if env_home:
        candidate = Path(env_home).expanduser() / "voice_input_bridge.swift"
        if candidate.is_file():
            return candidate.resolve()
    return Path(__file__).resolve().with_name("voice_input_bridge.swift")


def _voice_input_bridge_binary() -> Path:
    env_home = os.environ.get("CAPSWRITER_HOME", "").strip()
    if env_home:
        candidate = Path(env_home).expanduser() / "voice_input_bridge"
        if candidate.is_file():
            return candidate.resolve()
    return Path(__file__).resolve().with_name("voice_input_bridge")


def _ensure_voice_input_bridge_ready() -> bool:
    global _voice_input_bridge_ready, _voice_input_bridge_checked
    if _voice_input_bridge_ready:
        return True
    if _voice_input_bridge_checked and not _voice_input_bridge_ready:
        return False

    _voice_input_bridge_checked = True
    source = _voice_input_bridge_source()
    binary = _voice_input_bridge_binary()
    if not source.is_file():
        return False

    try:
        needs_build = (not binary.is_file()) or (source.stat().st_mtime > binary.stat().st_mtime)
    except Exception:
        needs_build = True

    try:
        if needs_build:
            subprocess.run(
                ["swiftc", "-O", str(source), "-o", str(binary)],
                timeout=40,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True,
            )
        _voice_input_bridge_ready = binary.is_file()
    except Exception as e:
        print(f"[Bridge] Swift 语音输入桥不可用: {e}", flush=True)
        _voice_input_bridge_ready = False

    return _voice_input_bridge_ready


def _run_voice_input_bridge(
    args: list[str],
    *,
    input_text: str | None = None,
    timeout: float = 5.0,
) -> subprocess.CompletedProcess:
    if not _ensure_voice_input_bridge_ready():
        raise RuntimeError("voice input bridge unavailable")
    binary = _voice_input_bridge_binary()
    return subprocess.run(
        [str(binary), *args],
        input=input_text,
        text=True,
        timeout=timeout,
        capture_output=True,
        check=False,
    )


def _voice_input_bridge_preflight() -> dict:
    try:
        result = _run_voice_input_bridge(["preflight"], timeout=3.0)
    except Exception:
        return {}

    stdout = (result.stdout or "").strip()
    if result.returncode != 0 or not stdout:
        return {}

    try:
        payload = json.loads(stdout.splitlines()[-1])
    except Exception:
        return {}
    return payload if isinstance(payload, dict) else {}


def _voice_input_bridge_microphone_payload(command: str, timeout: float) -> dict:
    try:
        result = _run_voice_input_bridge([command], timeout=timeout)
    except Exception:
        return {}

    stdout = (result.stdout or "").strip()
    if result.returncode != 0 or not stdout:
        return {}

    try:
        payload = json.loads(stdout.splitlines()[-1])
    except Exception:
        return {}
    return payload if isinstance(payload, dict) else {}


def _start_voice_hud() -> None:
    global _hud_proc
    if not _voice_hud_enabled():
        return
    if _hud_proc and _hud_proc.poll() is None:
        return

    script = _voice_hud_script()
    if not script.is_file():
        return

    try:
        _hud_proc = subprocess.Popen(
            _voice_hud_command(),
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
    except Exception as e:
        _hud_proc = None
        print(f"[HUD] 启动失败: {e}", flush=True)


def _send_voice_hud(payload: dict) -> None:
    global _hud_proc
    if not _voice_hud_enabled():
        return
    _start_voice_hud()
    if not _hud_proc or _hud_proc.poll() is not None or _hud_proc.stdin is None:
        return
    try:
        _hud_proc.stdin.write(json.dumps(payload, ensure_ascii=False) + "\n")
        _hud_proc.stdin.flush()
    except Exception:
        _hud_proc = None


def _set_voice_hud(status: str, text: str, timeout_ms: int = 0) -> None:
    _send_voice_hud(
        {
            "action": "show",
            "status": (status or "processing").strip().lower(),
            "text": (text or "").strip(),
            "timeout_ms": max(0, int(timeout_ms or 0)),
        }
    )


def _hide_voice_hud() -> None:
    _send_voice_hud({"action": "hide"})


def _stop_voice_hud() -> None:
    global _hud_proc
    if not _voice_hud_enabled():
        _hud_proc = None
        return
    if not _hud_proc:
        return
    try:
        _send_voice_hud({"action": "quit"})
    except Exception:
        pass
    try:
        if _hud_proc.stdin:
            _hud_proc.stdin.close()
    except Exception:
        pass
    try:
        _hud_proc.wait(timeout=0.8)
    except Exception:
        try:
            _hud_proc.terminate()
            _hud_proc.wait(timeout=1.5)
        except Exception:
            try:
                _hud_proc.kill()
            except Exception:
                pass
    _hud_proc = None


def _preflight_input_monitoring_access() -> bool:
    return bool(_voice_input_bridge_preflight().get("input_monitoring"))


def _preflight_post_event_access() -> bool:
    return bool(_voice_input_bridge_preflight().get("accessibility"))


def _probe_microphone_access_via_helper(timeout_s: float = 20.0) -> bool:
    helper_code = r"""
import sys
import time

import sounddevice as sd


def _preferred_capture_sample_rate(device):
    for key in ("default_samplerate", "samplerate"):
        try:
            value = float(device.get(key) or 0)
        except Exception:
            value = 0
        if value >= 8000:
            return value
    return 16000.0


device = sd.query_devices(kind="input")
channels = 1 if int(device.get("max_input_channels") or 0) >= 1 else 0
if channels <= 0:
    raise RuntimeError("未检测到可用麦克风声道")

sample_rate = _preferred_capture_sample_rate(device)
blocksize = max(256, int(0.05 * sample_rate))
stream = sd.InputStream(
    samplerate=sample_rate,
    blocksize=blocksize,
    dtype="float32",
    channels=channels,
    callback=lambda *args: None,
)
stream.start()
time.sleep(0.35)
stream.stop()
stream.close()
"""

    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"
    try:
        result = subprocess.run(
            [sys.executable, "-c", helper_code],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=max(3.0, float(timeout_s or 0.0)),
            check=False,
        )
        return result.returncode == 0
    except Exception:
        return False


def _microphone_auth_status_via_avfoundation(timeout_s: float = 4.0) -> str:
    payload = _voice_input_bridge_microphone_payload(
        "mic-preflight",
        timeout=max(2.0, float(timeout_s or 0.0)),
    )
    status = str((payload or {}).get("status") or "").strip().lower()
    if status in {"authorized", "denied", "restricted", "not_determined"}:
        return status
    return "unknown"


def _request_microphone_access_via_avfoundation(timeout_s: float = 20.0) -> bool:
    payload = _voice_input_bridge_microphone_payload(
        "mic-request",
        timeout=max(3.0, float(timeout_s or 0.0)),
    )
    status = str((payload or {}).get("status") or "").strip().lower()
    granted = bool((payload or {}).get("granted"))
    return granted or status == "authorized"


def _preflight_microphone_access() -> bool:
    status = _microphone_auth_status_via_avfoundation(timeout_s=3.0)
    if status == "authorized":
        return True
    if status in {"denied", "restricted", "not_determined"}:
        return False
    return _probe_microphone_access_via_helper(timeout_s=4.0)


def _request_microphone_access_via_sounddevice() -> bool:
    try:
        device = sd.query_devices(kind="input")
        channels = 1 if int(device.get("max_input_channels") or 0) >= 1 else 0
        if channels <= 0:
            return False
        sample_rate = _preferred_capture_sample_rate(device)
        stream = sd.InputStream(
            samplerate=sample_rate,
            blocksize=max(256, int(BLOCK_DURATION * sample_rate)),
            dtype="float32",
            channels=channels,
            callback=lambda *args: None,
        )
        stream.start()
        time.sleep(0.25)
        stream.stop()
        stream.close()
        return True
    except Exception:
        return False


def _request_microphone_access() -> bool:
    status = _microphone_auth_status_via_avfoundation(timeout_s=3.0)
    print(f"[权限] 麦克风授权状态: {status}", flush=True)

    if status == "authorized" or _preflight_microphone_access():
        print("[权限] 麦克风权限已就绪", flush=True)
        return True

    if status in {"denied", "restricted"}:
        app_name = "Vibecoding Keyboard" if getattr(sys, "frozen", False) else "当前程序"
        _set_voice_hud("error", "请允许麦克风访问", timeout_ms=_HUD_ERROR_TIMEOUT_MS)
        print("[权限] 麦克风权限未开启", flush=True)
        print("❌ 未获得麦克风权限，暂不启动语音输入。", flush=True)
        print(
            f"   请到 系统设置 -> 隐私与安全性 -> 麦克风，为 {app_name} 打开权限。",
            flush=True,
        )
        return False

    _set_voice_hud("starting", "请求麦克风权限")
    print("[权限] 正在请求麦克风权限...", flush=True)

    granted = _request_microphone_access_via_avfoundation(timeout_s=20.0)
    if not granted:
        # 兜底再尝试一次通过隔离 sounddevice 输入流触发系统授权。
        granted = _probe_microphone_access_via_helper(timeout_s=20.0)
    if not granted:
        granted = _request_microphone_access_via_sounddevice()

    if not granted:
        for _ in range(15):
            time.sleep(0.2)
            if _preflight_microphone_access():
                granted = True
                break

    if granted or _preflight_microphone_access():
        print("[权限] 麦克风权限已就绪", flush=True)
        return True

    app_name = "Vibecoding Keyboard" if getattr(sys, "frozen", False) else "当前程序"
    _set_voice_hud("error", "请允许麦克风访问", timeout_ms=_HUD_ERROR_TIMEOUT_MS)
    print("[权限] 麦克风权限未开启", flush=True)
    print("❌ 未获得麦克风权限，暂不启动语音输入。", flush=True)
    print(
        "   请先在系统弹出的麦克风授权框中点击“允许”。如果之前点过“不允许”，",
        flush=True,
    )
    print(
        f"   请到 系统设置 -> 隐私与安全性 -> 麦克风，为 {app_name} 打开权限。",
        flush=True,
    )
    return False


def _missing_manual_permission_labels() -> list[str]:
    labels = []
    if not _preflight_input_monitoring_access():
        labels.append("输入监控")
    if not _preflight_post_event_access():
        labels.append("辅助功能")
    return labels


def _permission_status_lines() -> list[str]:
    app_name = "Vibecoding Keyboard" if getattr(sys, "frozen", False) else "当前程序"
    lines = []
    for label in _missing_manual_permission_labels():
        if label == "输入监控":
            lines.append(
                f"   - 输入监控: 到 系统设置 -> 隐私与安全性 -> 输入监控，为 {app_name} 打开权限"
            )
        elif label == "辅助功能":
            lines.append(
                f"   - 辅助功能: 到 系统设置 -> 隐私与安全性 -> 辅助功能，为 {app_name} 打开权限"
            )
    return lines


def _request_runtime_permissions() -> bool:
    app_name = "Vibecoding Keyboard" if getattr(sys, "frozen", False) else "当前程序"
    if not _request_microphone_access():
        return False

    _set_voice_hud("starting", "检查系统权限")
    missing_manual = _missing_manual_permission_labels()
    missing_lines = _permission_status_lines()
    if not missing_lines and not missing_manual:
        return True

    _set_voice_hud("error", "请先完成系统授权", timeout_ms=_HUD_ERROR_TIMEOUT_MS)
    print(f"[权限] 需要手动开启: {'、'.join(missing_manual)}", flush=True)
    print(f"❌ 仍缺少系统权限，暂不启动 {VOICE_TRIGGER_LABEL} 监听。", flush=True)
    print("   请按下面的路径检查：", flush=True)
    for line in missing_lines:
        print(line, flush=True)
    print(f"   权限改完后，请彻底退出并重新打开 {app_name}。", flush=True)
    return False


def _typeless_config_path() -> Path:
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
    elif sys.platform == "darwin":
        base = str(Path.home() / "Library" / "Application Support")
    else:
        base = str(Path.home() / ".local" / "share")
    return Path(base) / "VibeKeyboard" / "typeless_config.json"


def _is_typeless_enabled() -> bool:
    path = _typeless_config_path()
    try:
        if not path.is_file():
            return False
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return bool((data or {}).get("typeless_enabled"))
    except Exception:
        return False


def _get_frontmost_app_info() -> tuple[str, str, int]:
    """避免触发额外自动化授权；当前默认不主动查询前台应用。"""
    name = _get_frontmost_app()
    return name, "", 0


def _activate_app_target(name: str = "", bundle_id: str = "") -> bool:
    """尽量把焦点切回录音开始前的目标应用。"""
    scripts: list[str] = []
    bundle_id = (bundle_id or "").strip()
    name = (name or "").strip()

    if bundle_id:
        escaped_bundle = bundle_id.replace('"', '\\"')
        scripts.append(f'tell application id "{escaped_bundle}" to activate')
    if name:
        escaped_name = name.replace('"', '\\"')
        scripts.append(f'tell application "{escaped_name}" to activate')

    for script in scripts:
        try:
            subprocess.run(
                ["osascript", "-e", script],
                timeout=2,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True,
            )
            time.sleep(0.08)
            current_name, current_bundle_id, _ = _resolve_live_insertion_target(wait_s=0.18, interval_s=0.04)
            if bundle_id and current_bundle_id == bundle_id:
                return True
            if name and current_name == name:
                return True
            if not bundle_id and name and current_name:
                return current_name == name
        except Exception:
            continue
    return False


def _resolve_live_insertion_target(wait_s: float = 0.35, interval_s: float = 0.05) -> tuple[str, str, int]:
    """在真正插入前短时间连续采样，尽量拿到最新且稳定的真实焦点应用。"""
    chosen_name = ""
    chosen_bundle_id = ""
    chosen_pid = 0
    last_seen = ("", "", 0)
    deadline = time.time() + max(0.0, wait_s)

    while True:
        name, bundle_id, pid = _get_frontmost_app_info()
        if name and not _looks_like_helper_app(name, bundle_id):
            current = (name, bundle_id, pid)
            if current == last_seen:
                return current
            chosen_name, chosen_bundle_id, chosen_pid = current
            last_seen = current

        if time.time() >= deadline:
            break
        time.sleep(interval_s)

    if chosen_name:
        return chosen_name, chosen_bundle_id, chosen_pid
    return "", "", 0


def _looks_like_helper_app(name: str, bundle_id: str = "") -> bool:
    joined = " ".join([(name or "").strip().lower(), (bundle_id or "").strip().lower()]).strip()
    if not joined:
        return False
    return any(token in joined for token in ("python", "pyside", "pyqt"))


def _current_pointer_location():
    return _last_pointer_point


def _refocus_record_pointer_location() -> bool:
    global _record_pointer_point
    point = _record_pointer_point
    if point is None:
        return False
    try:
        x, y = point
        result = _run_voice_input_bridge(["click", str(x), str(y)], timeout=3.0)
        return result.returncode == 0
    except Exception:
        return False


def _lock_frontmost_app_hint() -> None:
    """在浮层展示前尽快锁定当前目标应用，避免被 HUD 自身抢焦点后污染。"""
    global _frontmost_app_hint, _frontmost_app_hint_at, _frontmost_app_bundle_id, _frontmost_app_pid
    global _last_external_app_hint, _last_external_app_hint_at, _last_external_app_bundle_id, _last_external_app_pid
    t0 = time.time()
    name, bundle_id, pid = _get_frontmost_app_info()
    elapsed = time.time() - t0
    if name:
        if _looks_like_helper_app(name, bundle_id):
            if _last_external_app_hint:
                _frontmost_app_hint = _last_external_app_hint
                _frontmost_app_bundle_id = _last_external_app_bundle_id
                _frontmost_app_pid = _last_external_app_pid
                _frontmost_app_hint_at = _last_external_app_hint_at or time.time()
                print(
                    f"[上下文] 当前前台是辅助进程: {name}，沿用最近目标应用: {_last_external_app_hint} ({elapsed:.2f}s)",
                    flush=True,
                )
            else:
                print(f"[上下文] 当前前台是辅助进程，尚未找到可用目标应用: {name} ({elapsed:.2f}s)", flush=True)
            return
        _frontmost_app_hint = name
        _frontmost_app_bundle_id = bundle_id
        _frontmost_app_pid = pid
        _frontmost_app_hint_at = time.time()
        _last_external_app_hint = name
        _last_external_app_hint_at = _frontmost_app_hint_at
        _last_external_app_bundle_id = bundle_id
        _last_external_app_pid = pid
        print(f"[上下文] 锁定目标应用: {name} ({elapsed:.2f}s)", flush=True)
    else:
        print(f"[上下文] 锁定目标应用失败 ({elapsed:.2f}s)", flush=True)


def _refresh_frontmost_app_hint() -> None:
    """异步刷新前台应用缓存，尽量把耗时叠到用户录音阶段。"""
    global _frontmost_app_hint, _frontmost_app_hint_at, _frontmost_app_bundle_id, _frontmost_app_pid
    global _last_external_app_hint, _last_external_app_hint_at, _last_external_app_bundle_id, _last_external_app_pid
    t0 = time.time()
    app, bundle_id, pid = _get_frontmost_app_info()
    elapsed = time.time() - t0
    if app:
        if _looks_like_helper_app(app, bundle_id) and _frontmost_app_hint:
            print(f"[上下文] 忽略辅助进程前台应用: {app} ({elapsed:.2f}s)", flush=True)
            return
        _frontmost_app_hint = app
        _frontmost_app_bundle_id = bundle_id
        _frontmost_app_pid = pid
        _frontmost_app_hint_at = time.time()
        _last_external_app_hint = app
        _last_external_app_hint_at = _frontmost_app_hint_at
        _last_external_app_bundle_id = bundle_id
        _last_external_app_pid = pid
        print(f"[上下文] 前台应用: {app} ({elapsed:.2f}s)", flush=True)
    else:
        print(f"[上下文] 前台应用获取失败 ({elapsed:.2f}s)", flush=True)


def _ensure_frontmost_app_hint_async() -> None:
    Thread(target=_refresh_frontmost_app_hint, daemon=True).start()


def _ensure_text_injector_async() -> None:
    Thread(target=_warmup_text_injector, daemon=True).start()


def _restore_capslock():
    """清理旧版本可能留下的 hidutil CapsLock 重映射残留。"""
    global _capslock_is_remapped
    try:
        subprocess.run(
            ["hidutil", "property", "--set", '{"UserKeyMapping":[]}'],
            capture_output=True,
        )
        _capslock_is_remapped = False
        print("✅ CapsLock 映射已恢复", flush=True)
    except Exception:
        pass


def _preferred_capture_sample_rate(device: dict | None) -> int:
    default_rate = 0.0
    try:
        default_rate = float((device or {}).get("default_samplerate") or 0.0)
    except Exception:
        default_rate = 0.0

    if default_rate >= TARGET_SAMPLE_RATE:
        return int(round(default_rate))
    return TARGET_SAMPLE_RATE


def _coerce_audio_to_mono(data: np.ndarray) -> np.ndarray:
    global _channel_selection_logged
    array = np.asarray(data, dtype=np.float32)
    if array.ndim == 1:
        return np.ascontiguousarray(array, dtype=np.float32)
    if array.ndim != 2 or array.shape[1] <= 1:
        return np.ascontiguousarray(array.reshape(-1), dtype=np.float32)

    device_name = (_capture_device_name or "").strip().lower()
    is_builtin_mic = any(token in device_name for token in ("内建麦克风", "built-in", "microphone"))
    prefer_average = (sys.platform == "darwin" and os.uname().machine == "x86_64" and is_builtin_mic)

    # 这台老 Intel Mac 的内建麦克风实测更适合做双声道平均；
    # 否则很容易稳定识别成一个固定短词（例如“我”）。
    if prefer_average:
        if not _channel_selection_logged:
            _channel_selection_logged = True
            rms = np.sqrt(np.mean(np.square(array), axis=0))
            rms_values = ", ".join(f"{value:.5f}" for value in rms.tolist())
            print(
                f"[麦克风] 设备={_capture_device_name or '?'} 多声道输入={array.shape[1]}，"
                f"RMS=[{rms_values}]，旧款内建麦克风走双声道平均",
                flush=True,
            )
        return np.ascontiguousarray(np.mean(array, axis=1, dtype=np.float32), dtype=np.float32)

    # 其它设备继续走“选择能量最高单声道”。
    rms = np.sqrt(np.mean(np.square(array), axis=0))
    channel_index = int(np.argmax(rms))
    if not _channel_selection_logged:
        _channel_selection_logged = True
        rms_values = ", ".join(f"{value:.5f}" for value in rms.tolist())
        print(
            f"[麦克风] 设备={_capture_device_name or '?'} 多声道输入={array.shape[1]}，"
            f"RMS=[{rms_values}]，选择声道={channel_index}",
            flush=True,
        )
    return np.ascontiguousarray(array[:, channel_index], dtype=np.float32)


def _resample_audio(data: np.ndarray, source_rate: int, target_rate: int = TARGET_SAMPLE_RATE) -> np.ndarray:
    source = np.asarray(data, dtype=np.float32).reshape(-1)
    if source.size == 0:
        return np.ascontiguousarray(source, dtype=np.float32)

    src = max(1, int(source_rate or target_rate))
    dst = max(1, int(target_rate))
    if src == dst:
        return np.ascontiguousarray(source, dtype=np.float32)

    if source.size == 1:
        repeats = max(1, int(round(dst / src)))
        return np.ascontiguousarray(np.repeat(source, repeats), dtype=np.float32)

    duration = source.size / float(src)
    out_length = max(1, int(round(duration * dst)))
    xp = np.arange(source.size, dtype=np.float32)
    positions = np.linspace(0.0, float(source.size - 1), num=out_length, dtype=np.float32)
    resampled = np.interp(positions, xp, source).astype(np.float32)
    return np.ascontiguousarray(resampled, dtype=np.float32)


def _encode_audio_payload(data: np.ndarray) -> str:
    mono = _coerce_audio_to_mono(data)
    normalized = _resample_audio(mono, _capture_sample_rate, TARGET_SAMPLE_RATE)
    if normalized.size == 0:
        return ""
    return base64.b64encode(normalized.tobytes()).decode("utf-8")


def _debug_audio_dir() -> Path:
    return (
        Path.home()
        / "Library"
        / "Application Support"
        / "VibeKeyboard"
        / "capswriter"
        / "debug"
    )


def _write_debug_recording(samples: np.ndarray, *, peak: float, rms: float, gain: float) -> None:
    global _record_debug_dump_index
    try:
        debug_dir = _debug_audio_dir()
        debug_dir.mkdir(parents=True, exist_ok=True)
        wav_path = debug_dir / "last_recording.wav"
        meta_path = debug_dir / "last_recording.json"
        pcm = np.clip(np.asarray(samples, dtype=np.float32), -1.0, 1.0)
        pcm16 = (pcm * 32767.0).astype(np.int16)
        with wave.open(str(wav_path), "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(TARGET_SAMPLE_RATE)
            wf.writeframes(pcm16.tobytes())
        _record_debug_dump_index += 1
        meta = {
            "sequence": _record_debug_dump_index,
            "sample_rate": TARGET_SAMPLE_RATE,
            "num_samples": int(pcm.size),
            "duration_seconds": round(float(pcm.size) / float(TARGET_SAMPLE_RATE), 4),
            "peak": round(float(peak), 6),
            "rms": round(float(rms), 6),
            "gain": round(float(gain), 4),
            "capture_device": _capture_device_name,
            "capture_sample_rate": _capture_sample_rate,
            "capture_channels": _capture_channels,
        }
        meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception as exc:
        print(f"[麦克风] 调试录音落盘失败: {exc}", flush=True)


def _write_empty_recording_debug(*, reason: str, duration_seconds: float) -> None:
    global _record_debug_dump_index
    try:
        debug_dir = _debug_audio_dir()
        debug_dir.mkdir(parents=True, exist_ok=True)
        wav_path = debug_dir / "last_recording.wav"
        meta_path = debug_dir / "last_recording.json"

        with wave.open(str(wav_path), "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(TARGET_SAMPLE_RATE)
            wf.writeframes(b"")

        _record_debug_dump_index += 1
        meta = {
            "sequence": _record_debug_dump_index,
            "reason": reason,
            "sample_rate": TARGET_SAMPLE_RATE,
            "num_samples": 0,
            "duration_seconds": round(float(duration_seconds), 4),
            "peak": 0.0,
            "rms": 0.0,
            "gain": 1.0,
            "capture_device": _capture_device_name,
            "capture_sample_rate": _capture_sample_rate,
            "capture_channels": _capture_channels,
        }
        meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception as exc:
        print(f"[麦克风] 空录音调试落盘失败: {exc}", flush=True)


def _prepare_utterance_payload(data: np.ndarray) -> str:
    mono = _coerce_audio_to_mono(data)
    samples = _resample_audio(mono, _capture_sample_rate, TARGET_SAMPLE_RATE)
    if samples.size == 0:
        return ""

    samples = np.asarray(samples, dtype=np.float32)
    samples = samples - np.mean(samples, dtype=np.float32)

    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    rms = float(np.sqrt(np.mean(np.square(samples)))) if samples.size else 0.0
    if peak <= 1e-7 or rms <= 1e-7:
        print("[麦克风] 本次录音几乎是静音，取消发送", flush=True)
        return ""
    if peak < 0.00025 and rms < 0.00003:
        print(
            f"[麦克风] 本次录音电平过低（peak={peak:.6f}, rms={rms:.6f}），"
            "判定为近静音，取消发送",
            flush=True,
        )
        _write_debug_recording(samples, peak=peak, rms=rms, gain=1.0)
        return ""
    if peak < 0.003 and rms < 0.00035:
        print(
            f"[麦克风] 本次录音电平偏低（peak={peak:.6f}, rms={rms:.6f}），"
            "继续尝试自动增益补偿",
            flush=True,
        )

    # 对这台老 Intel Mac 的内建麦克风做温和自动增益。
    # 目标是把正常说话声拉到模型更容易稳定识别的电平范围，
    # 同时限制最大增益，避免把底噪放大得太夸张。
    target_peak = 0.28
    target_rms = 0.045
    peak_gain = target_peak / max(peak, 1e-7)
    rms_gain = target_rms / max(rms, 1e-7)
    gain = min(160.0, max(1.0, min(peak_gain, rms_gain)))

    boosted = np.clip(samples * gain, -1.0, 1.0).astype(np.float32)
    boosted_peak = float(np.max(np.abs(boosted))) if boosted.size else 0.0
    boosted_rms = float(np.sqrt(np.mean(np.square(boosted)))) if boosted.size else 0.0
    print(
        f"[麦克风] 本次录音: 输入峰值={peak:.6f}, 输入RMS={rms:.6f}, "
        f"增益={gain:.2f}x, 输出峰值={boosted_peak:.6f}, 输出RMS={boosted_rms:.6f}",
        flush=True,
    )
    _write_debug_recording(boosted, peak=boosted_peak, rms=boosted_rms, gain=gain)
    return base64.b64encode(boosted.tobytes()).decode("utf-8")


# ── 音频回调 ──────────────────────────────────────────
def _audio_callback(indata: np.ndarray, frames, time_info, status):
    global _recording
    if not _recording or _loop is None or _queue is None:
        return
    if time.time() < _record_audio_gate_until:
        return
    asyncio.run_coroutine_threadsafe(
        _queue.put({"type": "data", "time": time.time(), "data": indata.copy()}),
        _loop,
    )


def _begin_recording() -> None:
    global _recording, _record_start, _task_id, _record_pointer_point, _record_audio_gate_until
    if _recording:
        return
    _lock_frontmost_app_hint()
    _recording = True
    _record_start = time.time()
    _refresh_audio_cue_config()
    cue_gate_seconds = _START_CUE_GATE_SECONDS if _audio_cue_is_enabled() else 0.0
    _record_audio_gate_until = _record_start + cue_gate_seconds
    _task_id = str(uuid.uuid1())
    _record_pointer_point = _current_pointer_location()
    _set_voice_hud("recording", "录音中")
    play_start_cue()
    print(f"\n🔴 录音中... (松开停止)", flush=True)
    if _loop and _queue:
        asyncio.run_coroutine_threadsafe(
            _queue.put({"type": "begin", "time": _record_start, "data": None}),
            _loop,
        )


def _finish_recording() -> None:
    global _recording
    if not _recording:
        return
    duration = time.time() - _record_start
    _recording = False
    _set_voice_hud("processing", "本地识别中")
    play_stop_cue()
    print(f"⏹ 录音结束，时长 {duration:.2f}s，识别中...", flush=True)
    if _loop and _queue:
        asyncio.run_coroutine_threadsafe(
            _queue.put({"type": "finish", "time": time.time(), "data": None}),
            _loop,
        )


def _schedule_long_press_start(token: int) -> None:
    def _delayed_start() -> None:
        time.sleep(VOICE_TRIGGER_LONG_PRESS_SECONDS)
        if token != _voice_trigger_token:
            return
        if not _voice_trigger_pressed:
            return
        _begin_recording()

    Thread(target=_delayed_start, daemon=True).start()


def _handle_voice_trigger_key_down() -> None:
    global _voice_trigger_pressed, _voice_trigger_started_at, _voice_trigger_token
    if _voice_trigger_pressed:
        return
    _voice_trigger_pressed = True
    _voice_trigger_started_at = time.time()
    _voice_trigger_token += 1
    _schedule_long_press_start(_voice_trigger_token)


def _handle_voice_trigger_key_up() -> None:
    global _voice_trigger_pressed, _voice_trigger_token
    if not _voice_trigger_pressed:
        return
    _voice_trigger_pressed = False
    _voice_trigger_token += 1
    if _recording:
        _finish_recording()


def _handle_voice_input_bridge_payload(payload: dict) -> None:
    global _last_pointer_point

    event_type = (payload.get("type") or "").strip().lower()
    if event_type == "ready":
        print(f"✅ 按键事件监听已启动（等待 {VOICE_TRIGGER_LABEL}）", flush=True)
        return

    if event_type == "pointer":
        try:
            _last_pointer_point = (float(payload.get("x")), float(payload.get("y")))
        except Exception:
            pass
        return

    if event_type == "key_down":
        _handle_voice_trigger_key_down()
        return

    if event_type == "key_up":
        _handle_voice_trigger_key_up()
        return

    if event_type == "error":
        _set_voice_hud("error", "需要系统权限", timeout_ms=_HUD_ERROR_TIMEOUT_MS)
        print(f"❌ 语音输入桥启动失败: {payload.get('message', 'unknown')}", flush=True)
        if payload.get("input_monitoring") is False:
            print("   请到 系统设置 → 隐私与安全性 → 输入监控，为 Vibecoding Keyboard 打开权限。", flush=True)
        if payload.get("accessibility") is False:
            print("   请到 系统设置 → 隐私与安全性 → 辅助功能，为 Vibecoding Keyboard 打开权限。", flush=True)


def _stop_voice_input_bridge() -> None:
    global _voice_input_bridge_proc
    proc = _voice_input_bridge_proc
    _voice_input_bridge_proc = None
    if proc is None or proc.poll() is not None:
        return
    try:
        proc.terminate()
        proc.wait(timeout=1.0)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass


def _start_event_tap():
    global _voice_input_bridge_proc
    if _voice_input_bridge_proc is not None and _voice_input_bridge_proc.poll() is None:
        return

    if not _ensure_voice_input_bridge_ready():
        _set_voice_hud("error", "语音监听不可用", timeout_ms=_HUD_ERROR_TIMEOUT_MS)
        print("❌ Swift 语音输入桥不可用，无法监听语音键。", flush=True)
        return

    binary = _voice_input_bridge_binary()
    try:
        proc = subprocess.Popen(
            [str(binary), "monitor"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
    except Exception as exc:
        _set_voice_hud("error", "语音监听不可用", timeout_ms=_HUD_ERROR_TIMEOUT_MS)
        print(f"❌ 启动 Swift 语音输入桥失败: {exc}", flush=True)
        return

    _voice_input_bridge_proc = proc

    def _read_stdout() -> None:
        stream = proc.stdout
        if stream is None:
            return
        try:
            for raw_line in iter(stream.readline, ""):
                line = raw_line.strip()
                if not line:
                    continue
                try:
                    payload = json.loads(line)
                except Exception:
                    print(f"[Bridge] {line}", flush=True)
                    continue
                if isinstance(payload, dict):
                    _handle_voice_input_bridge_payload(payload)
        finally:
            try:
                stream.close()
            except Exception:
                pass

    def _read_stderr() -> None:
        stream = proc.stderr
        if stream is None:
            return
        try:
            for raw_line in iter(stream.readline, ""):
                line = raw_line.strip()
                if line:
                    print(f"[Bridge] {line}", flush=True)
        finally:
            try:
                stream.close()
            except Exception:
                pass

    Thread(target=_read_stdout, daemon=True).start()
    Thread(target=_read_stderr, daemon=True).start()


# ── 文字输出（粘贴到光标位置）──────────────────────────
def _paste_via_quartz() -> None:
    """通过 Swift helper 投递 Cmd+V。"""
    result = _run_voice_input_bridge(["paste"], timeout=3.0)
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout or "voice bridge paste failed").strip())


def _type_text_via_quartz_unicode(text: str) -> None:
    """通过 Swift helper 像真实键盘一样发送 Unicode 文本。"""
    if not (text or ""):
        return
    result = _run_voice_input_bridge(["type"], input_text=text, timeout=8.0)
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout or "voice bridge type failed").strip())


def _copy_text_to_clipboard(text: str) -> None:
    """使用 pbcopy 写入系统剪贴板，避免 AppKit 导入。"""
    proc = subprocess.Popen(["pbcopy"], stdin=subprocess.PIPE)
    proc.communicate(text.encode("utf-8"))


def _read_focused_text_fast(timeout_s: float = 0.6) -> str:
    """禁用 System Events 校验，避免首次使用时弹自动化授权。"""
    return ""


def _paste_via_applescript() -> None:
    _paste_via_quartz()


def _paste_via_menu_action() -> None:
    _paste_via_quartz()


def _type_text_via_applescript(text: str) -> None:
    _type_text_via_quartz_unicode(text)


def _insert_text_via_ax_helper(text: str) -> None:
    if not _ensure_text_injector_ready():
        raise RuntimeError("swift text injector unavailable")
    binary = _text_injector_binary()
    result = subprocess.run(
        [str(binary)],
        input=text,
        text=True,
        timeout=5,
        capture_output=True,
    )
    stdout = (result.stdout or "").strip()
    stderr = (result.stderr or "").strip()
    if stdout:
        print(f"  [AX] {stdout}", flush=True)
    if result.returncode != 0:
        raise RuntimeError(stderr or stdout or f"exit={result.returncode}")


def _verify_focused_text_contains(expected: str) -> bool | None:
    """尝试读取当前焦点控件文本；无法读取时返回 None。"""
    try:
        focused = _read_focused_text_fast().strip()
    except Exception:
        return None
    if not focused:
        return None
    normalized_expected = (expected or "").strip()
    if not normalized_expected:
        return None
    return (normalized_expected in focused) or focused.endswith(normalized_expected)


def _paste_text(text: str):
    """优先回到录音开始前最后一次鼠标落点，再把文本粘贴回去。"""
    if TRASH_PUNC:
        text = re.sub(f"(?<=.)[{re.escape(TRASH_PUNC)}]$", "", text)
    text = (text or "").strip()
    if not text:
        _set_voice_hud("ready", "未识别到内容", timeout_ms=_HUD_READY_TIMEOUT_MS)
        print("  [阶段] 未识别到有效文本，取消粘贴", flush=True)
        return
    print(f"\n✏️  识别结果: {text}", flush=True)
    # 1. 复制到剪贴板
    try:
        t0 = time.time()
        _copy_text_to_clipboard(text)
        print(f"  [阶段] 已复制到剪贴板 ({time.time() - t0:.2f}s)", flush=True)
    except Exception as e:
        _set_voice_hud("error", "复制失败", timeout_ms=_HUD_ERROR_TIMEOUT_MS)
        print(f"  [pbcopy 失败] {e}", flush=True)
        return
    # 2. 按当前系统焦点写入文本
    _set_voice_hud("processing", "准备粘贴")
    try:
        _hide_voice_hud()
        time.sleep(0.08)
        refocused_pointer = False
        activated = False
        if _record_pointer_point is not None and _should_refocus_record_pointer():
            refocused_pointer = _refocus_record_pointer_location()
        if refocused_pointer:
            time.sleep(0.18)
            print("  [阶段] 已回到录音开始时的鼠标位置", flush=True)
        elif _frontmost_app_hint or _frontmost_app_bundle_id:
            activated = _activate_app_target(_frontmost_app_hint, _frontmost_app_bundle_id)
            if activated:
                print(
                    f"  [阶段] 已恢复目标应用: {_frontmost_app_hint or _frontmost_app_bundle_id}",
                    flush=True,
                )
                time.sleep(0.12)
        t1 = time.time()
        _paste_via_quartz()
        verify = _verify_focused_text_contains(text)
        if verify is True:
            print("  [阶段] 焦点文本校验通过", flush=True)
        elif verify is False:
            raise RuntimeError("quartz paste finished but focused text does not contain expected content")
        else:
            print("  [阶段] 焦点文本不可读，未校验 Quartz 粘贴结果", flush=True)
        _hide_voice_hud()
        print(f"  ✅ 已粘贴到当前焦点 ({time.time() - t1:.2f}s, Quartz 粘贴)\n", flush=True)
    except Exception as quartz_paste_error:
        print(f"  [Quartz 粘贴失败] {quartz_paste_error}", flush=True)
        try:
            t2 = time.time()
            _type_text_via_quartz_unicode(text)
            verify = _verify_focused_text_contains(text)
            if verify is True:
                print("  [阶段] 焦点文本校验通过", flush=True)
            elif verify is False:
                raise RuntimeError("quartz unicode typing finished but focused text does not contain expected content")
            else:
                print("  [阶段] 焦点文本不可读，未校验 Quartz Unicode 直输结果", flush=True)
            _hide_voice_hud()
            print(f"  ✅ 已写入当前焦点 ({time.time() - t2:.2f}s, Quartz Unicode 直输回退)\n", flush=True)
        except Exception as unicode_error:
            print(f"  [Quartz Unicode 直输失败] {unicode_error}", flush=True)
            try:
                t3 = time.time()
                _insert_text_via_ax_helper(text)
                verify = _verify_focused_text_contains(text)
                if verify is True:
                    print("  [阶段] 焦点文本校验通过", flush=True)
                elif verify is False:
                    raise RuntimeError("ax helper finished but focused text does not contain expected content")
                else:
                    print("  [阶段] 焦点文本不可读，跳过插入校验", flush=True)
                _hide_voice_hud()
                print(
                    f"  ✅ 已写入当前焦点 ({time.time() - t3:.2f}s, AX 直写回退)\n",
                    flush=True,
                )
            except Exception as ax_error:
                _set_voice_hud("error", "粘贴失败", timeout_ms=_HUD_ERROR_TIMEOUT_MS)
                print(
                    f"  [粘贴失败] QuartzPaste={quartz_paste_error}; QuartzUnicode={unicode_error}; AX={ax_error}，请手动 Cmd+V\n",
                    flush=True,
                )


# ── 主异步逻辑 ────────────────────────────────────────
async def _record_and_send():
    """从队列读音频数据，整段录完后统一送给服务器。"""
    global _ws
    utterance_frames = []
    task_id = ""
    start_time = 0.0

    while True:
        item = await _queue.get()
        _queue.task_done()

        if item["type"] == "begin":
            task_id = _task_id
            start_time = item["time"]
            utterance_frames.clear()

        elif item["type"] == "data":
            if not task_id:
                continue
            utterance_frames.append(item["data"])

        elif item["type"] == "finish":
            if not task_id:
                continue
            payload = ""
            if utterance_frames:
                try:
                    data = np.concatenate(utterance_frames, axis=0)
                except Exception:
                    data = utterance_frames[-1]
                utterance_frames.clear()
                payload = _prepare_utterance_payload(data)
            else:
                duration = max(0.0, float(item["time"]) - float(start_time or item["time"]))
                _write_empty_recording_debug(
                    reason="no_audio_frames",
                    duration_seconds=duration,
                )
                print(
                    f"[麦克风] 本次录音未采到音频帧（duration={duration:.3f}s），取消识别",
                    flush=True,
                )
                utterance_frames.clear()

            if not payload:
                _set_voice_hud("ready", "未检测到有效语音", timeout_ms=_HUD_READY_TIMEOUT_MS)
                print("[麦克风] 本次录音未生成有效音频，取消识别", flush=True)
                task_id = ""
                continue

            msg = {
                "task_id": task_id,
                "seg_duration": 15,
                "seg_overlap": 2,
                "is_final": True,
                "time_start": start_time,
                "time_frame": item["time"],
                "source": "mic",
                "data": payload,
                "context": "",
            }
            if _ws:
                await _ws.send(json.dumps(msg))
            task_id = ""

        elif item["type"] == "cancel":
            utterance_frames.clear()
            task_id = ""


async def _receive_results():
    """接收服务器返回的识别结果"""
    global _ws
    while True:
        try:
            raw = await _ws.recv()
            msg = json.loads(raw)
            if msg.get("is_final"):
                text = msg.get("text", "")
                delay = msg.get("time_complete", 0) - msg.get("time_submit", 0)
                print(f"[识别] {text}  (时延 {delay:.2f}s)")
                typeless_enabled = _is_typeless_enabled()
                if typeless_enabled:
                    _set_voice_hud("processing", "AhaType整理中")
                else:
                    _set_voice_hud("processing", "准备粘贴")
                text = optimize_text(text, app_name="")
                if not (text or "").strip():
                    _set_voice_hud("ready", "未识别到内容", timeout_ms=_HUD_READY_TIMEOUT_MS)
                    print("[识别] 未识别到有效文本，取消粘贴", flush=True)
                    continue
                _set_voice_hud("processing", "准备粘贴")
                _paste_text(text)
                # 粘贴后触发纠错学习（延迟检测用户修正）
                schedule_learning(text)
        except websockets.ConnectionClosedError:
            _set_voice_hud("starting", "等待语音服务")
            print("[连接断开] 尝试重连...")
            break
        except Exception as e:
            _set_voice_hud("error", "语音结果接收异常", timeout_ms=_HUD_ERROR_TIMEOUT_MS)
            print(f"[接收错误] {e}")
            break


async def _main():
    global _loop, _queue, _ws, _capture_sample_rate, _capture_channels, _capture_device_name

    _loop = asyncio.get_running_loop()
    _queue = asyncio.Queue()
    stream = None

    try:
        # 1. 先检查系统权限，避免在无权限时进入半初始化状态
        _start_voice_hud()
        _set_voice_hud("starting", "语音启动中")
        if not _request_runtime_permissions():
            return

        # 2. 清理旧版本可能留下的 CapsLock 重映射残留
        _restore_capslock()
        atexit.register(_restore_capslock)
        atexit.register(_stop_voice_hud)
        atexit.register(_stop_voice_input_bridge)

        # 3. 打开音频流
        device = sd.query_devices(kind="input")
        max_input_channels = int(device.get("max_input_channels") or 0)
        channels = min(max_input_channels, 2) if max_input_channels >= 1 else 0
        if channels <= 0:
            raise RuntimeError("未检测到可用麦克风声道")

        sample_rate = _preferred_capture_sample_rate(device)
        _capture_sample_rate = sample_rate
        _capture_channels = channels
        _capture_device_name = str(device.get("name") or "")
        blocksize = max(256, int(round(BLOCK_DURATION * sample_rate)))
        print(
            f"麦克风: {device.get('name', '?')}, 声道: {channels}, 输入采样率: {sample_rate}Hz, 发送采样率: {TARGET_SAMPLE_RATE}Hz",
            flush=True,
        )

        stream = sd.InputStream(
            samplerate=sample_rate,
            blocksize=blocksize,
            dtype="float32",
            channels=channels,
            callback=_audio_callback,
        )
        stream.start()

        # 4. 启动 Quartz EventTap 监听独立语音触发键（F18）
        tap_thread = Thread(target=_start_event_tap, daemon=True)
        tap_thread.start()

        # 5. 连接 ASR 服务器
        url = f"ws://127.0.0.1:{SERVER_PORT}"
        _set_voice_hud("starting", "等待语音服务")
        print(f"正在连接 {url} ...", flush=True)

        connect_kwargs = dict(subprotocols=["binary"], max_size=None)
        try:
            import inspect
            sig = inspect.signature(websockets.connect)
            if "proxy" in sig.parameters:
                connect_kwargs["proxy"] = None
        except Exception:
            pass

        while True:
            try:
                async with websockets.connect(url, **connect_kwargs) as ws:
                    _ws = ws
                    _set_voice_hud("ready", "语音已就绪", timeout_ms=_HUD_READY_TIMEOUT_MS)
                    print("", flush=True)
                    print("✅ 已连接到 ASR 服务器", flush=True)
                    print("━" * 40, flush=True)
                    print("短按 CapsLock → macOS 原生切换大小写 / 输入法", flush=True)
                    print(f"长按 {VOICE_TRIGGER_LABEL}（约 {VOICE_TRIGGER_LONG_PRESS_SECONDS:.2f}s）→ 开始录音", flush=True)
                    print(f"松开 {VOICE_TRIGGER_LABEL} → 停止并识别", flush=True)
                    print("识别结果自动粘贴到光标位置", flush=True)
                    print("━" * 40, flush=True)
                    print("", flush=True)
                    send_task = asyncio.create_task(_record_and_send())
                    recv_task = asyncio.create_task(_receive_results())
                    done, pending = await asyncio.wait(
                        [send_task, recv_task], return_when=asyncio.FIRST_COMPLETED
                    )
                    for t in pending:
                        t.cancel()
            except ConnectionRefusedError:
                _set_voice_hud("starting", "等待语音服务")
                print(f"连接被拒绝，5 秒后重试...", flush=True)
            except Exception as e:
                _set_voice_hud("error", "语音服务连接异常", timeout_ms=_HUD_ERROR_TIMEOUT_MS)
                print(f"连接错误: {e}，5 秒后重试...", flush=True)
            _ws = None
            await asyncio.sleep(5)
    finally:
        _ws = None
        try:
            if stream is not None:
                stream.stop()
                stream.close()
        except Exception:
            pass
        _stop_voice_input_bridge()
        _restore_capslock()
        _stop_voice_hud()


if __name__ == "__main__":
    print("=" * 50)
    print("CapsWriter macOS Client")
    print("  短按 CapsLock → macOS 原生切换大小写 / 输入法")
    print(f"  长按 {VOICE_TRIGGER_LABEL}（约 {VOICE_TRIGGER_LONG_PRESS_SECONDS:.2f}s）→ 录音")
    print(f"  松开 {VOICE_TRIGGER_LABEL} → 识别")
    print("=" * 50)
    try:
        asyncio.run(_main())
    except KeyboardInterrupt:
        _stop_voice_hud()
        _restore_capslock()
        print("\n再见！")

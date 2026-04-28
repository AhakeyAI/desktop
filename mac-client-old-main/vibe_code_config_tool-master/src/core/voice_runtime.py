"""Helpers for launching the embedded CapsWriter runtime."""

from __future__ import annotations

import os
import runpy
import sys
from pathlib import Path
from typing import List, Optional


CAPSWRITER_HOME_ENV = "CAPSWRITER_HOME"
CAPSWRITER_BOOTSTRAP_EXE_ENV = "CAPSWRITER_BOOTSTRAP_EXE"
_BOOTSTRAP_FLAG = "--capswriter-bootstrap"
_HOME_FLAG = "--capswriter-home"


def prepare_capswriter_environment_from_env() -> None:
    """Make the external CapsWriter runtime importable for frozen child processes."""
    home = os.environ.get(CAPSWRITER_HOME_ENV, "").strip()
    if not home:
        return

    try:
        resolved = str(Path(home).expanduser().resolve())
    except OSError:
        return

    if not Path(resolved).is_dir():
        return

    if resolved not in sys.path:
        sys.path.insert(0, resolved)


def preferred_voice_runtime_homes() -> List[Path]:
    """Return the voice runtime locations we should prefer before legacy fallbacks."""
    candidates: List[Path] = []

    env_home = os.environ.get(CAPSWRITER_HOME_ENV, "").strip()
    if env_home:
        candidates.append(Path(env_home).expanduser())

    if getattr(sys, "frozen", False) and sys.platform == "darwin":
        exe_path = Path(sys.executable).resolve()
        candidates.append(exe_path.parents[1] / "Resources" / "capswriter")

    repo_root = Path(__file__).resolve().parents[2]
    candidates.append(repo_root / "capswriter")

    unique: List[Path] = []
    seen = set()
    for candidate in candidates:
        try:
            resolved = candidate.resolve()
        except OSError:
            continue
        if resolved in seen:
            continue
        seen.add(resolved)
        unique.append(resolved)
    return unique


def build_embedded_voice_command(entry: str, tool_dir: Path) -> Optional[List[str]]:
    """Launch embedded voice scripts via the main frozen executable."""
    if not getattr(sys, "frozen", False):
        return None

    bootstrap_exe = os.environ.get(CAPSWRITER_BOOTSTRAP_EXE_ENV, "").strip() or sys.executable
    return [
        bootstrap_exe,
        _BOOTSTRAP_FLAG,
        entry,
        _HOME_FLAG,
        str(tool_dir),
    ]


def maybe_run_embedded_voice_runtime(argv: Optional[List[str]] = None) -> bool:
    """Handle hidden bootstrap flags used by the packaged app."""
    args = list(sys.argv[1:] if argv is None else argv)
    if _BOOTSTRAP_FLAG not in args:
        return False

    entry = _read_flag_value(args, _BOOTSTRAP_FLAG)
    home_arg = _read_flag_value(args, _HOME_FLAG)
    home = _resolve_voice_home(home_arg)
    script_path = _resolve_entry_script(entry, home)

    os.environ[CAPSWRITER_HOME_ENV] = str(home)
    os.environ[CAPSWRITER_BOOTSTRAP_EXE_ENV] = sys.executable
    _configure_bootstrap_process(entry)
    prepare_capswriter_environment_from_env()
    os.chdir(home)
    sys.argv = [str(script_path)]
    runpy.run_path(str(script_path), run_name="__main__")
    return True


def _read_flag_value(args: List[str], flag: str) -> str:
    try:
        index = args.index(flag)
    except ValueError as exc:
        raise SystemExit(f"缺少参数: {flag}") from exc

    if index + 1 >= len(args):
        raise SystemExit(f"参数缺少取值: {flag}")

    value = args[index + 1].strip()
    if not value:
        raise SystemExit(f"参数取值为空: {flag}")
    return value


def _resolve_voice_home(home_arg: Optional[str]) -> Path:
    if home_arg:
        candidate = Path(home_arg).expanduser()
        if candidate.is_dir():
            return candidate.resolve()
        raise SystemExit(f"CapsWriter 目录不存在: {candidate}")

    for candidate in preferred_voice_runtime_homes():
        if candidate.is_dir():
            return candidate

    raise SystemExit("未找到可用的 CapsWriter 运行目录")


def _resolve_entry_script(entry: str, home: Path) -> Path:
    script_name = _entry_to_script_name(entry)
    script_path = home / script_name
    if script_path.is_file():
        return script_path
    raise SystemExit(f"未找到语音入口脚本: {script_path}")


def _entry_to_script_name(entry: str) -> str:
    normalized = (entry or "").strip()
    if normalized in {"start_server", "core_server"}:
        return "core_server.py"
    if normalized in {"start_client", "core_client_mac"} and sys.platform == "darwin":
        return "core_client_mac.py"
    if normalized in {"start_client", "core_client"}:
        return "core_client.py"
    if normalized in {"voice_hud", "hud"}:
        return "voice_hud.py"
    raise SystemExit(f"不支持的语音入口: {entry}")


def _configure_bootstrap_process(entry: str) -> None:
    # The packaged bootstrap processes run through the same frozen executable as
    # the main GUI app. Importing AppKit here to tweak activation policy can
    # deadlock in PyInstaller/PySide lazy imports on some macOS machines,
    # leaving voice server/client spinning before their scripts even start.
    #
    # Keep bootstrap launch simple and let each entry script manage its own UI
    # behavior instead of forcing activation policy at process start.
    return


def _set_macos_activation_policy(policy: str) -> None:
    try:
        from AppKit import (
            NSApplication,
            NSApplicationActivationPolicyAccessory,
            NSApplicationActivationPolicyProhibited,
        )
    except Exception:
        return

    try:
        app = NSApplication.sharedApplication()
        if policy == "accessory":
            app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)
        else:
            app.setActivationPolicy_(NSApplicationActivationPolicyProhibited)
    except Exception:
        return

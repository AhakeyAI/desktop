"""Embedded Claude/Cursor hook dispatcher for packaged app builds."""

from __future__ import annotations

import importlib
import sys
from pathlib import Path


HOOK_MODULES = {
    "SessionStart": "SessionStart",
    "SessionEnd": "SessionEnd",
    "PreToolUse": "PreToolUse",
    "PostToolUse": "PostToolUse",
    "PermissionRequest": "PermissionRequest",
    "Notification": "Notification",
    "TaskCompleted": "TaskCompleted",
    "Stop": "Stop",
    "UserPromptSubmit": "UserPromptSubmit",
    "sessionStart": "SessionStart",
    "sessionEnd": "SessionEnd",
    "preToolUse": "PreToolUse",
    "postToolUse": "PostToolUse",
    "stop": "Stop",
}


def _ensure_hook_import_path() -> None:
    if getattr(sys, "frozen", False):
        return

    hook_dir = Path(__file__).resolve().parents[2] / "hook"
    if hook_dir.is_dir():
        hook_dir_str = str(hook_dir)
        if hook_dir_str not in sys.path:
            sys.path.insert(0, hook_dir_str)


def maybe_run_embedded_hook_runtime(argv: list[str] | None = None) -> bool:
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 2 or args[0] != "--hook-dispatch":
        return False

    event_name = (args[1] or "").strip()
    module_name = HOOK_MODULES.get(event_name)
    if not module_name:
        raise SystemExit(f"Unknown hook event: {event_name}")

    _ensure_hook_import_path()
    module = importlib.import_module(module_name)
    run = getattr(module, "run", None)
    if not callable(run):
        raise SystemExit(f"Hook module {module_name} has no callable run()")
    run()
    return True

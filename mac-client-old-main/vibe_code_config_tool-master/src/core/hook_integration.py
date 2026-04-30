"""Helpers for locating, launching, and invoking the Hook manager."""

from __future__ import annotations

import json
import os
import plistlib
import shlex
import subprocess
import sys
from pathlib import Path


def _load_json(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        with path.open("r", encoding="utf-8") as file:
            return json.load(file)
    except (OSError, json.JSONDecodeError):
        return {}


def _has_hooks(path: Path) -> bool:
    data = _load_json(path)
    hooks = data.get("hooks")
    if isinstance(hooks, dict):
        return any(bool(value) for value in hooks.values())
    return False


def _iter_hook_commands(path: Path):
    data = _load_json(path)
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return

    for definitions in hooks.values():
        if not isinstance(definitions, list):
            continue
        for definition in definitions:
            if not isinstance(definition, dict):
                continue
            direct_command = definition.get("command")
            if isinstance(direct_command, str) and direct_command.strip():
                yield direct_command.strip()
            for hook in definition.get("hooks", []) or []:
                if not isinstance(hook, dict):
                    continue
                command = hook.get("command")
                if isinstance(command, str) and command.strip():
                    yield command.strip()


def _uses_legacy_hook_manager_runtime(path: Path) -> bool:
    legacy_markers = (
        "hook_install.app/Contents/MacOS/hook_install",
        "\\hook_install.exe",
        "/hook_install.exe",
    )
    for command in _iter_hook_commands(path):
        if "--hook-dispatch" in command:
            continue
        if any(marker in command for marker in legacy_markers):
            return True
    return False


def claude_hooks_installed() -> bool:
    return _has_hooks(Path.home() / ".claude" / "settings.json")


def cursor_hooks_installed() -> bool:
    return _has_hooks(Path.home() / ".cursor" / "hooks.json")


def claude_hooks_need_migration() -> bool:
    return _uses_legacy_hook_manager_runtime(Path.home() / ".claude" / "settings.json")


def cursor_hooks_need_migration() -> bool:
    return _uses_legacy_hook_manager_runtime(Path.home() / ".cursor" / "hooks.json")


def hook_targets_needing_migration() -> list[str]:
    targets: list[str] = []
    if claude_hooks_need_migration():
        targets.append("Claude")
    if cursor_hooks_need_migration():
        targets.append("Cursor")
    return targets


def hooks_need_attention() -> bool:
    return not claude_hooks_installed() or not cursor_hooks_installed()


def missing_hook_targets() -> list[str]:
    missing: list[str] = []
    if not claude_hooks_installed():
        missing.append("Claude")
    if not cursor_hooks_installed():
        missing.append("Cursor")
    return missing


def find_hook_manager() -> Path | None:
    candidates: list[Path] = []

    if getattr(sys, "frozen", False):
        exe_path = Path(sys.executable).resolve()
        if sys.platform == "darwin":
            resources_dir = exe_path.parents[1] / "Resources"
            candidates.append(resources_dir / "bundled_apps" / "hook_install.app")
            candidates.append(resources_dir / "hook_install.app")
            candidates.append(exe_path.parents[3] / "hook_install.app")
        candidates.append(exe_path.with_name("hook_install.exe"))
        candidates.append(exe_path.with_name("hook_install"))

    repo_root = Path(__file__).resolve().parents[2]
    candidates.extend(
        [
            repo_root / "hook" / "dist" / "hook_install.app",
            repo_root / "hook" / "hook_install.py",
            repo_root / "hook" / "hook_install.exe",
        ]
    )

    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None


def _bundle_executable(app_bundle: Path) -> Path | None:
    if app_bundle.suffix != ".app":
        return None

    macos_dir = app_bundle / "Contents" / "MacOS"
    if not macos_dir.is_dir():
        return None

    plist_path = app_bundle / "Contents" / "Info.plist"
    if plist_path.is_file():
        try:
            with plist_path.open("rb") as file:
                data = plistlib.load(file)
            executable_name = str(data.get("CFBundleExecutable") or "").strip()
            if executable_name:
                executable_path = macos_dir / executable_name
                if executable_path.is_file():
                    return executable_path
        except Exception:
            pass

    for candidate in sorted(macos_dir.iterdir()):
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def _find_hook_cli_target() -> list[str] | None:
    target = find_hook_manager()
    if target is None:
        return None

    if target.suffix == ".app" and sys.platform == "darwin":
        executable = _bundle_executable(target)
        if executable is not None:
            return [str(executable)]
        return None

    if target.suffix == ".py":
        return [sys.executable, str(target)]

    return [str(target)]


def launch_hook_manager() -> bool:
    target = find_hook_manager()
    if target is None:
        return False

    if target.suffix == ".app" and sys.platform == "darwin":
        executable = _bundle_executable(target)
        if executable is not None:
            try:
                subprocess.Popen(
                    [str(executable)],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    cwd=str(target.parent),
                )
                return True
            except OSError:
                pass
        try:
            subprocess.Popen(
                [
                    "/bin/sh",
                    "-c",
                    (
                        f"open -na {shlex.quote(str(target))} >/dev/null 2>&1; "
                        "sleep 0.35; "
                        "osascript -e 'tell application id \"com.vibekeyboard.hookinstall\" "
                        "to activate' >/dev/null 2>&1 || true"
                    ),
                ],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return True
        except OSError:
            return False

    if target.suffix == ".py":
        subprocess.Popen([sys.executable, str(target)])
        return True

    subprocess.Popen([str(target)])
    return True


def maybe_launch_hook_manager() -> bool:
    if not hooks_need_attention():
        return False
    return launch_hook_manager()


def run_hook_manager_command(*args: str, timeout: int = 30) -> tuple[bool, str]:
    command = _find_hook_cli_target()
    if command is None:
        return False, "当前打包版内置的是图形化 Hook 管理器，请改为打开 Hook 管理器完成安装。"

    try:
        result = subprocess.run(
            [*command, *args],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return False, str(exc)

    output = "\n".join(
        part.strip()
        for part in (result.stdout, result.stderr)
        if part and part.strip()
    ).strip()

    if result.returncode == 0:
        return True, output or "Hook 操作已完成。"
    return False, output or f"Hook 管理工具退出码异常: {result.returncode}"


def install_missing_hooks() -> tuple[bool, str]:
    missing = missing_hook_targets()
    if not missing:
        return True, "Claude 与 Cursor hooks 都已安装。"

    if len(missing) == 2:
        return run_hook_manager_command("--install-all")
    if missing == ["Claude"]:
        return run_hook_manager_command("--install-claude")
    return run_hook_manager_command("--install-cursor")


def refresh_legacy_hooks() -> tuple[bool, str]:
    targets = hook_targets_needing_migration()
    if not targets:
        return True, "现有 Hook 已经使用轻量运行时，无需迁移。"

    if len(targets) == 2:
        return run_hook_manager_command("--install-all")
    if targets == ["Claude"]:
        return run_hook_manager_command("--install-claude")
    return run_hook_manager_command("--install-cursor")


def supports_automatic_hook_install() -> bool:
    target = find_hook_manager()
    if target is None:
        return False

    return _find_hook_cli_target() is not None

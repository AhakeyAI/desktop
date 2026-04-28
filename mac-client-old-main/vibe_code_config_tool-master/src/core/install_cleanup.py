"""Helpers for post-install cleanup on macOS."""

from __future__ import annotations

import os
import stat
import subprocess
import sys
from pathlib import Path


_APP_BUNDLE_NAME = "Vibecoding Keyboard.app"
_LAUNCH_AGENT_LABEL = "com.vibekeyboard.uninstallwatch"


def current_app_bundle_path() -> Path | None:
    """Return the current .app bundle root when running from a frozen macOS app."""
    if sys.platform != "darwin" or not getattr(sys, "frozen", False):
        return None

    try:
        return Path(sys.executable).resolve().parents[2]
    except OSError:
        return None


def _cleanup_support_dir() -> Path:
    return (
        Path.home()
        / "Library"
        / "Application Support"
        / "VibeKeyboard"
        / "cleanup"
    )


def _launch_agent_path() -> Path:
    return Path.home() / "Library" / "LaunchAgents" / f"{_LAUNCH_AGENT_LABEL}.plist"


def _cleanup_script_path() -> Path:
    return _cleanup_support_dir() / "watch_uninstall.sh"


def _cleanup_log_path() -> Path:
    return _cleanup_support_dir() / "watch_uninstall.log"


def _write_cleanup_script(app_bundle_path: Path) -> Path:
    support_dir = _cleanup_support_dir()
    support_dir.mkdir(parents=True, exist_ok=True)

    script_path = _cleanup_script_path()
    trash_dir = Path.home() / ".Trash"
    launch_agent = _launch_agent_path()
    script = f"""#!/bin/sh
APP_PATH={_sh_quote(str(app_bundle_path))}
TRASH_DIR={_sh_quote(str(trash_dir))}
PLIST_PATH={_sh_quote(str(launch_agent))}
SUPPORT_DIR={_sh_quote(str(support_dir))}
LOG_FILE={_sh_quote(str(_cleanup_log_path()))}

if [ -d "$APP_PATH" ]; then
  exit 0
fi

TRASH_APP=""
for candidate in "$TRASH_DIR"/*.app; do
  [ -d "$candidate" ] || continue
  INFO_PLIST="$candidate/Contents/Info.plist"
  if [ -f "$INFO_PLIST" ] && /usr/bin/grep -q "<string>com.vibekeyboard.keyboardconfig</string>" "$INFO_PLIST"; then
    TRASH_APP="$candidate"
    break
  fi
done

if [ -z "$TRASH_APP" ]; then
  exit 0
fi

HOOK_TOOL="$TRASH_APP/Contents/Resources/bundled_apps/hook_install.app/Contents/MacOS/hook_install"
if [ -x "$HOOK_TOOL" ]; then
  "$HOOK_TOOL" --uninstall-all >>"$LOG_FILE" 2>&1 || true
fi

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH" "$0"
rm -rf "$SUPPORT_DIR"
exit 0
"""

    script_path.write_text(script, encoding="utf-8")
    current_mode = script_path.stat().st_mode
    script_path.chmod(current_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return script_path


def _write_launch_agent(script_path: Path, app_bundle_path: Path) -> Path:
    plist_path = _launch_agent_path()
    plist_path.parent.mkdir(parents=True, exist_ok=True)

    trash_dir = Path.home() / ".Trash"
    log_path = _cleanup_log_path()
    plist = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>{_xml_escape(_LAUNCH_AGENT_LABEL)}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>{_xml_escape(str(script_path))}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>WatchPaths</key>
  <array>
    <string>{_xml_escape(str(app_bundle_path))}</string>
    <string>{_xml_escape(str(trash_dir))}</string>
  </array>
  <key>StandardOutPath</key>
  <string>{_xml_escape(str(log_path))}</string>
  <key>StandardErrorPath</key>
  <string>{_xml_escape(str(log_path))}</string>
</dict>
</plist>
"""
    plist_path.write_text(plist, encoding="utf-8")
    return plist_path


def _xml_escape(text: str) -> str:
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&apos;")
    )


def _sh_quote(text: str) -> str:
    return "'" + text.replace("'", "'\"'\"'") + "'"


def _run_launchctl(*args: str) -> bool:
    try:
        subprocess.run(
            ["launchctl", *args],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def ensure_uninstall_watcher() -> None:
    """Install or refresh a LaunchAgent that cleans hooks when the app is trashed."""
    app_bundle_path = current_app_bundle_path()
    if app_bundle_path is None:
        return
    if app_bundle_path.is_relative_to(Path("/Volumes")):
        return
    if app_bundle_path.is_relative_to(Path.home() / ".Trash"):
        return

    script_path = _write_cleanup_script(app_bundle_path)
    plist_path = _write_launch_agent(script_path, app_bundle_path)

    uid = str(os.getuid())
    _run_launchctl("bootout", f"gui/{uid}", str(plist_path))
    _run_launchctl("unload", str(plist_path))
    if _run_launchctl("bootstrap", f"gui/{uid}", str(plist_path)):
        return
    _run_launchctl("load", "-w", str(plist_path))


def maybe_eject_installer_volume() -> None:
    """Best-effort eject the mounted installer DMG after the app is launched from Applications."""
    app_bundle_path = current_app_bundle_path()
    if app_bundle_path is None:
        return

    volumes_dir = Path("/Volumes")
    if not volumes_dir.is_dir():
        return

    for mount_point in volumes_dir.iterdir():
        try:
            resolved_mount = mount_point.resolve()
        except OSError:
            continue

        if app_bundle_path.is_relative_to(resolved_mount):
            continue

        mounted_app = resolved_mount / _APP_BUNDLE_NAME
        applications_link = resolved_mount / "Applications"
        install_guide = resolved_mount / "安装说明.txt"
        if not mounted_app.is_dir():
            continue
        if not applications_link.exists():
            continue
        if not install_guide.exists():
            continue

        try:
            subprocess.Popen(
                ["hdiutil", "detach", str(resolved_mount), "-force"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError:
            pass
        break

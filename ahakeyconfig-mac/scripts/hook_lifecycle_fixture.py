"""Loopback model-call detector for isolated hook lifecycle scripts."""
import http.server
import threading
from pathlib import Path


def policy_swift_sources(shared):
    """The real dependency closure used by standalone policy fixture compilers."""
    return [shared / name for name in (
        "CodexConfigLeverSync.swift", "ApprovalAutomationControl.swift",
        "CodexDesktopSessionBridge.swift", "CodexDesktopLeverState.swift",
        "CursorApprovalPolicySync.swift", "KimiConfigPolicySync.swift", "CodexHookTrust.swift",
    )]


def ensure_claude_fixture_isolated(policy_root=Path("/Library/Application Support/ClaudeCode"), preference_probe=None):
    """User-config redirection does not disable machine-wide Claude policies."""
    import subprocess
    for name in ("managed-settings.json", "managed-settings.d", "managed-mcp.json", "CLAUDE.md"):
        path = policy_root / name
        if path.exists() or path.is_symlink():
            raise RuntimeError("Managed Claude configuration present; isolated fixture cannot run")
    if preference_probe is None:
        def preference_probe():
            result = subprocess.run(["/usr/bin/defaults", "read", "com.anthropic.claudecode"],
                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, timeout=5)
            if result.returncode == 0:
                return True
            if result.returncode == 1 and "does not exist" in result.stderr:
                return False
            raise RuntimeError("Cannot confirm absence of managed Claude preferences")
    if preference_probe():
        raise RuntimeError("Claude preference policy present; isolated fixture cannot run")


class ForbiddenModelEndpoint:
    def __enter__(self):
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                self.server.calls += 1
                self.send_error(503, "A lifecycle fixture must not call a model")

            def log_message(self, *args):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.calls = 0
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        return self

    def __exit__(self, *args):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)


def terminate_process_group(process, grace_seconds=2):
    """Reap our fixture parent and confirm its whole process group is gone."""
    import os
    import signal
    import subprocess
    import time

    def group_exists():
        try:
            os.killpg(process.pid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            # Darwin can return EPERM for an orphan group containing only
            # zombies. Inspect that exact group: zombies cannot execute and
            # only their adopting parent can reap them. A live member still
            # counts as a cleanup failure; EPERM alone never means success.
            result = subprocess.run(["/bin/ps", "-axo", "pgid=,stat="],
                capture_output=True, text=True, check=True, timeout=3)
            for line in result.stdout.splitlines():
                fields = line.split()
                if len(fields) == 2 and fields[0] == str(process.pid) and not fields[1].startswith("Z"):
                    return True
            return False

    for stop_signal in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, stop_signal)
        except ProcessLookupError:
            break
        except PermissionError:
            if not group_exists():
                break
            raise
        deadline = time.monotonic() + grace_seconds
        while time.monotonic() < deadline:
            # poll also reaps an exited parent; its status alone does not prove
            # its subprocesses have exited.
            process.poll()
            if not group_exists():
                break
            time.sleep(.02)
        if not group_exists():
            break
    if process.poll() is None:
        try:
            process.wait(timeout=grace_seconds)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError("Fixture parent survived cleanup") from error
    if group_exists():
        raise RuntimeError("Fixture process group survived cleanup")

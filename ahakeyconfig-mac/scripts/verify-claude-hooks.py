#!/usr/bin/env python3
"""Run production Claude hook lifecycle in an isolated home without real auth/model.

A user UserPromptSubmit hook blocks each prompt. Any model request fails the
fixture. --live-reload checks hook replacement/removal in one persistent process.
Neither mode proves live physical lever behavior.
"""
import argparse
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import tempfile
import threading
import time

from hook_lifecycle_fixture import ForbiddenModelEndpoint, ensure_claude_fixture_isolated, terminate_process_group

SWIFT = r'''
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let mode = CommandLine.arguments[2]
let directory = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "agent's space"
let config = root.appendingPathComponent("settings.json")
let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
let result = mode == "remove" ? try JSONHooksConfiguration.removing(in: settings, client: .claude)
    : try JSONHooksConfiguration.installing(in: settings, client: .claude,
        agentPath: root.appendingPathComponent(directory + "/ahakeyconfig-agent").path)
try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]).write(to: config, options: .atomic)
'''


def verify_live_reload(cli, root, generator, env, endpoint):
    """Wait for each blocked turn before changing the actual user settings file."""
    replacement = root / "next agent's space/ahakeyconfig-agent"
    replacement.parent.mkdir()
    replacement.write_text('#!/bin/sh\ncat >/dev/null\nprintf "next:%s\\n" "$2" >> "$CLAUDE_CONFIG_DIR/markers"\nprintf "{}\\n"\n')
    replacement.chmod(0o700)
    subprocess.run([str(generator), str(root), "initial"], check=True, timeout=5)
    messages = queue.Queue()
    process = subprocess.Popen([cli, "--print", "--verbose", "--input-format", "stream-json",
        "--output-format", "stream-json", "--setting-sources", "user", "--no-session-persistence",
        "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}', "--tools", ""],
        env=env, cwd=root / "work", stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, text=True, start_new_session=True)

    def read_messages():
        for line in process.stdout:
            try:
                messages.put(json.loads(line))
            except ValueError:
                pass
        messages.put(None)

    reader = threading.Thread(target=read_messages, daemon=True)
    reader.start()
    results = {}
    try:
        for stage in ("initial", "replace", "remove"):
            if stage != "initial":
                subprocess.run([str(generator), str(root), stage, "next agent's space"], check=True, timeout=5)
                # Claude waits for file stability. A blocked-turn fixture must
                # also let parallel managed hooks finish before user rejection.
                time.sleep(2.5)
            assert process.poll() is None, "Persistent Claude process exited"
            marker = root / "markers"
            marker.unlink(missing_ok=True)
            process.stdin.write(json.dumps({"type": "user", "message": {
                "role": "user", "content": "Blocked local reload fixture: " + stage}}) + "\n")
            process.stdin.flush()
            deadline = time.monotonic() + 15
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("No blocked-turn result for " + stage)
                try:
                    message = messages.get(timeout=remaining)
                except queue.Empty as error:
                    raise TimeoutError("No blocked-turn result for " + stage) from error
                assert message is not None, "Claude exited before completing " + stage
                if message.get("type") == "result":
                    break
            executed = set(marker.read_text().splitlines()) if marker.exists() else set()
            assert "user" in executed and endpoint.server.calls == 0, "User block did not prevent model request"
            if stage == "initial":
                assert "UserPromptSubmit" in executed, executed
            elif stage == "replace":
                assert "next:UserPromptSubmit" in executed and "UserPromptSubmit" not in executed, executed
            else:
                assert executed == {"user"}, executed
            assert process.poll() is None, "A new process cannot prove hot reload"
            results[stage] = {"executed": sorted(executed), "sameProcess": True}
        return results
    finally:
        terminate_process_group(process)
        process.stdin.close()
        reader.join(timeout=2)
        process.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", default=shutil.which("claude"))
    parser.add_argument("--live-reload", action="store_true", help="Replace/remove hooks in one persistent native CLI")
    args = parser.parse_args()
    if not args.cli:
        parser.error("Claude Code is required")
    ensure_claude_fixture_isolated()
    version = subprocess.check_output([args.cli, "--version"], text=True, timeout=5).strip()
    with tempfile.TemporaryDirectory(prefix="ahakey-claude-lifecycle-") as directory, ForbiddenModelEndpoint() as endpoint:
        root = Path(directory).resolve()
        (root / "main.swift").write_text(SWIFT)
        source = Path(__file__).resolve().parents[1] / "Sources/Shared/JSONHooksConfiguration.swift"
        generator = root / "generate"
        subprocess.run(["swiftc", str(source), str(root / "main.swift"), "-o", str(generator)], check=True, timeout=60)
        agent = root / "agent's space/ahakeyconfig-agent"
        agent.parent.mkdir()
        agent.write_text('#!/bin/sh\ncat >/dev/null\nprintf "%s\\n" "$2" >> "$CLAUDE_CONFIG_DIR/markers"\nprintf "{}\\n"\n')
        agent.chmod(0o700)
        user = root / "user-hook.sh"
        user.write_text('#!/bin/sh\ncat >/dev/null\nprintf "user\\n" >> "$CLAUDE_CONFIG_DIR/markers"\nprintf "AHAKEY_CLAUDE_FIXTURE_BLOCKED\\n" >&2\n/bin/sleep .2\nexit 2\n')
        user.chmod(0o700)
        original = {"hooks": {"UserPromptSubmit": [{"matcher": "", "hooks": [{"type": "command", "command": "/bin/sh " + str(user)}]}]}}
        config = root / "settings.json"
        config.write_text(json.dumps(original))
        env = {key: os.environ[key] for key in ("PATH", "TMPDIR", "LANG") if key in os.environ}
        env.update(CLAUDE_CONFIG_DIR=str(root), ANTHROPIC_API_KEY="offline-fixture-only",
                   ANTHROPIC_BASE_URL=f"http://127.0.0.1:{endpoint.server.server_port}",
                   CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1", DISABLE_AUTOUPDATER="1")
        if args.live_reload:
            (root / "work").mkdir()
            results = verify_live_reload(args.cli, root, generator, env, endpoint)
            print(json.dumps({"cli": version, "liveReload": results, "modelRequests": endpoint.server.calls,
                "scope": "same-process hook replacement/removal; no live lever control claimed"}, indent=2))
            return
        results = {}
        previous = None
        for stage in ("initial", "reinstall", "remove"):
            subprocess.run([str(generator), str(root), stage], check=True, timeout=5)
            actual = json.loads(config.read_text())
            if stage == "reinstall":
                assert actual == previous, "Reinstall changed hooks"
            previous = actual
            count = sum(len(group["hooks"]) for groups in actual.get("hooks", {}).values() for group in groups)
            assert count == (1 if stage == "remove" else 12), count
            marker = root / "markers"
            marker.unlink(missing_ok=True)
            result = subprocess.run([args.cli, "--print", "Blocked local lifecycle fixture.",
                "--setting-sources", "", "--settings", str(config), "--no-session-persistence",
                "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}', "--tools", ""],
                env=env, cwd=root, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=25)
            executed = set(marker.read_text().splitlines()) if marker.exists() else set()
            assert "user" in executed, "Retained user hook did not execute: " + (result.stdout + result.stderr)[-1000:]
            assert endpoint.server.calls == 0, "Blocked prompt reached model"
            if stage == "remove":
                assert executed == {"user"}, "Managed hook survived removal"
                assert actual == original, "Removal changed user configuration"
            else:
                assert {"SessionStart", "UserPromptSubmit"} <= executed, executed
            results[stage] = {"hooks": count, "executed": sorted(executed), "exit": result.returncode}
        print(json.dumps({"cli": version, "lifecycle": results, "modelRequests": endpoint.server.calls}, indent=2))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Run production Claude hook lifecycle in an isolated home without real auth/model.

A user UserPromptSubmit hook blocks each prompt. Any model request fails the
fixture. This does not prove live physical lever behavior or session hot reload.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from hook_lifecycle_fixture import ForbiddenModelEndpoint

SWIFT = r'''
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let mode = CommandLine.arguments[2]
let config = root.appendingPathComponent("settings.json")
let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
let result = mode == "remove" ? try JSONHooksConfiguration.removing(in: settings, client: .claude)
    : try JSONHooksConfiguration.installing(in: settings, client: .claude,
        agentPath: root.appendingPathComponent("agent's space/ahakeyconfig-agent").path)
try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]).write(to: config)
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", default=shutil.which("claude"))
    args = parser.parse_args()
    if not args.cli:
        parser.error("Claude Code is required")
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
        user.write_text('#!/bin/sh\ncat >/dev/null\nprintf "user\\n" >> "$CLAUDE_CONFIG_DIR/markers"\nprintf "AHAKEY_CLAUDE_FIXTURE_BLOCKED\\n" >&2\nexit 2\n')
        user.chmod(0o700)
        original = {"hooks": {"UserPromptSubmit": [{"matcher": "", "hooks": [{"type": "command", "command": "/bin/sh " + str(user)}]}]}}
        config = root / "settings.json"
        config.write_text(json.dumps(original))
        env = {key: os.environ[key] for key in ("PATH", "TMPDIR", "LANG") if key in os.environ}
        env.update(CLAUDE_CONFIG_DIR=str(root), ANTHROPIC_API_KEY="offline-fixture-only",
                   ANTHROPIC_BASE_URL=f"http://127.0.0.1:{endpoint.server.server_port}",
                   CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1", DISABLE_AUTOUPDATER="1")
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

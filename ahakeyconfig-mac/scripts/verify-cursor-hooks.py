#!/usr/bin/env python3
"""Exercise production Cursor hook install/reinstall/remove at CLI startup/exit.

No real credentials or provider are used. Metadata comes from a loopback fixture;
the Agent stream is deliberately unsupported. A bounded CLI failure is expected,
so this proves startup/exit hooks only, not prompt/tool callbacks or live approval.
"""
import argparse
import base64
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading

from hook_lifecycle_fixture import terminate_process_group

SWIFT = r'''
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let url = root.appendingPathComponent(".cursor/hooks.json")
let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
let next = CommandLine.arguments[2] == "remove" ? try JSONHooksConfiguration.removing(in: settings, client: .cursor)
    : try JSONHooksConfiguration.installing(in: settings, client: .cursor,
        agentPath: root.appendingPathComponent("agent's space/ahakeyconfig-agent").path)
try JSONSerialization.data(withJSONObject: next, options: [.sortedKeys]).write(to: url)
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", default=shutil.which("agent"))
    args = parser.parse_args()
    if not args.cli:
        parser.error("Cursor Agent CLI is required")
    # Managed system hooks cannot be redirected by the public config variables.
    if Path("/Library/Application Support/Cursor/hooks.json").exists():
        parser.error("enterprise hooks present; this isolated fixture cannot run safely")
    version = subprocess.check_output([args.cli, "--version"], text=True, timeout=5).strip()
    with tempfile.TemporaryDirectory(prefix="ahakey-cursor-lifecycle-", dir="/tmp") as directory:
        root = Path(directory)
        (root / ".cursor").mkdir()
        (root / "work").mkdir()
        calls = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                if length > 4 * 1024 * 1024:
                    self.send_error(413)
                    return
                self.rfile.read(length)
                calls.append(self.path)
                if self.path == "/auth/exchange_user_api_key":
                    def encode(value):
                        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")
                    token = encode({"alg": "none"}) + "." + encode({"sub": "fixture-user", "exp": 4102444800}) + ".fixture"
                    body = json.dumps({"accessToken": token, "refreshToken": "fixture-only"}).encode()
                    content_type = "application/json"
                else:
                    # Minimal protobuf ModelDetails(model_id="fixture") wrapped
                    # in the actual model-list/default response field.
                    body = b"\x0a\x09\x0a\x07fixture" if self.path.endswith(("/GetDefaultModelForCli", "/GetUsableModels")) else b""
                    content_type = "application/proto"
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            (root / "main.swift").write_text(SWIFT)
            source = Path(__file__).resolve().parents[1] / "Sources/Shared/JSONHooksConfiguration.swift"
            generator = root / "generate"
            subprocess.run(["swiftc", str(source), str(root / "main.swift"), "-o", str(generator)], check=True, timeout=60)
            agent = root / "agent's space/ahakeyconfig-agent"
            agent.parent.mkdir()
            agent.write_text('#!/bin/sh\ncat >/dev/null\nprintf "%s\\n" "$2" >> "$AHAKEY_FIXTURE_ROOT/markers"\nprintf "{}\\n"\n')
            agent.chmod(0o700)
            user = root / "user-hook.sh"
            user.write_text('#!/bin/sh\ncat >/dev/null\necho user >> "$AHAKEY_FIXTURE_ROOT/markers"\nprintf "{}\\n"\n')
            user.chmod(0o700)
            original = {"version": 1, "hooks": {"sessionStart": [{"command": "/bin/sh " + str(user)}]}}
            config = root / ".cursor/hooks.json"
            config.write_text(json.dumps(original))
            # Test process only: actual hook discovery ignores CURSOR_CONFIG_DIR
            # and calls os.homedir(). Keep both Cursor and Claude imports isolated.
            preload = root / "isolate.cjs"
            preload.write_text('require("node:os").homedir=()=>process.env.AHAKEY_FIXTURE_ROOT;require("node:module").syncBuiltinESMExports();')
            env = {key: os.environ[key] for key in ("TMPDIR", "LANG") if key in os.environ}
            env.update(PATH="/usr/bin:/bin:/usr/sbin:/sbin", AHAKEY_FIXTURE_ROOT=str(root),
                CURSOR_CONFIG_DIR=str(root / ".cursor"), CURSOR_DATA_DIR=str(root / ".cursor"),
                CURSOR_AGENT_STORE_DIR=str(root / "store"), AGENT_CLI_CREDENTIAL_STORE="file",
                CURSOR_API_KEY="offline-fixture", CURSOR_API_ENDPOINT=f"http://127.0.0.1:{server.server_port}",
                NODE_OPTIONS="--require=" + str(preload), NODE_COMPILE_CACHE=str(root / "cache"), npm_config_offline="true")
            results = {}
            previous = None
            for stage in ("initial", "reinstall", "remove"):
                subprocess.run([str(generator), str(root), stage], check=True, timeout=5)
                actual = json.loads(config.read_text())
                if stage == "reinstall":
                    assert actual == previous, "Reinstall is not idempotent"
                previous = actual
                count = sum(len(entries) for entries in actual["hooks"].values())
                assert count == (1 if stage == "remove" else 10), count
                marker = root / "markers"
                marker.unlink(missing_ok=True)
                process = subprocess.Popen([args.cli, "--print", "--trust", "--model", "fixture",
                    "--workspace", str(root / "work"), "Offline startup fixture."], cwd=root / "work", env=env,
                    stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
                try:
                    stdout, stderr = process.communicate(timeout=30)
                finally:
                    terminate_process_group(process)
                executed = set(marker.read_text().splitlines()) if marker.exists() else set()
                assert process.returncode == 1 and "Protocol error" in stdout + stderr, "Unexpected CLI failure"
                assert "user" in executed, "User hook was removed or not loaded"
                if stage == "remove":
                    assert actual == original and executed == {"user"}, "Managed hooks survived removal"
                else:
                    assert {"sessionStart", "sessionEnd"} <= executed, executed
                results[stage] = {"configuredHooks": count, "executed": sorted(executed), "expectedStreamFailure": True}
            print(json.dumps({"cli": version, "lifecycle": results,
                "scope": "startup/exit only; loopback metadata and unsupported Agent stream; no real model/provider",
                "promptAndToolCallbacks": "not verified"}, indent=2))
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == "__main__":
    main()

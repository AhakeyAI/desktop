#!/usr/bin/env python3
"""Verify native Codex per-request grants and old-session bypass protection.

Only local marker files run. --legacy-bypass simulates an already-open old
session. Lever facts are synthetic; physical BLE and real Agent IPC are not
claimed. No account or external model provider is used.
"""
import argparse
import http.server
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import tempfile
import threading
import time

from hook_lifecycle_fixture import terminate_process_group

SWIFT = r'''import Foundation
import Darwin
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let operation = CommandLine.arguments[2]
let url = root.appendingPathComponent("config.toml")
let control = root.appendingPathComponent("approval-control")
if operation == "setup" {
    let text = try String(contentsOf: url, encoding: .utf8)
    let next = try CodexHookTrust.installAgentHooks(in: text, configPath: url.path,
        agentBinaryPath: root.appendingPathComponent("agent's space/ahakeyconfig-agent").path)
    try next.write(to: url, atomically: true, encoding: .utf8)
} else if operation == "legacy" {
    _ = CodexConfigLeverSync.apply(switchStateAuto: true, configURL: url, controlDirectory: control)
} else if operation == "hook" {
    let event = CommandLine.arguments[3]
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    let entry: [String: Any] = ["event": event, "mode": input["permission_mode"] ?? NSNull()]
    let line = try JSONSerialization.data(withJSONObject: entry) + Data([10])
    let fd = open(root.appendingPathComponent("hook-events").path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
    guard fd >= 0 else { exit(2) }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    try handle.write(contentsOf: line)
    try handle.close()
    let flag = try String(contentsOf: root.appendingPathComponent("lever"), encoding: .utf8)
    let verified = flag == "auto" && ApprovalAutomationControl.isEnabled(.codex, directory: control)
    var output: [String: Any] = [:]
    if event == "CodexSessionStart" {
        _ = CodexConfigLeverSync.prepareHookManagedSession(configURL: url, controlDirectory: control)
    } else if event == "CodexPermissionRequest" {
        _ = CodexConfigLeverSync.prepareHookManagedSession(configURL: url, controlDirectory: control)
        output = CodexHookApproval.permissionRequestOutput(verifiedAuto: verified)
    } else if event == "CodexPreToolUse", CodexHookApproval.requiresPreToolVerification(permissionMode: input["permission_mode"] as? String) {
        _ = CodexConfigLeverSync.prepareHookManagedSession(configURL: url, controlDirectory: control)
        output = CodexHookApproval.bypassPreToolOutput(verifiedAuto: verified) ?? [:]
    }
    print(String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self))
} else {
    _ = CodexConfigLeverSync.prepareHookManagedSession(configURL: url, controlDirectory: control)
}
'''


class LocalResponses:
    def __init__(self, workspace, legacy):
        self.workspace = workspace
        self.legacy = legacy
        self.requests = 0
        self.stage = "auto"

    def __enter__(self):
        owner = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.reply(b'{"object":"list","data":[]}', "application/json")

            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                if length > 4 * 1024 * 1024:
                    self.send_error(413)
                    return
                self.rfile.read(length)
                owner.requests += 1
                count = owner.requests
                identity = "fixture-" + str(count)
                events = [{"type": "response.created", "response": {"id": identity}}]
                if count % 2:
                    command = "printf safe > '" + str(owner.workspace / ("marker-" + owner.stage)) + "'"
                    arguments = {"cmd": command, "yield_time_ms": 1000}
                    if not owner.legacy:
                        arguments.update(sandbox_permissions="require_escalated", justification="Run only a temporary local fixture marker")
                    item = {"type": "function_call", "name": "exec_command", "call_id": "call_" + str(count), "arguments": json.dumps(arguments)}
                else:
                    item = {"type": "message", "role": "assistant", "id": "msg_" + str(count),
                        "content": [{"type": "output_text", "text": "Local fixture complete."}]}
                events.append({"type": "response.output_item.done", "item": item})
                events.append({"type": "response.completed", "response": {"id": identity,
                    "usage": {"input_tokens": 0, "output_tokens": 0, "total_tokens": 0}}})
                body = "".join("event: " + event["type"] + "\ndata: " + json.dumps(event) + "\n\n" for event in events)
                self.reply(body.encode(), "text/event-stream")

            def reply(self, body, content_type):
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.server.server_port}/v1"
        return self

    def __exit__(self, *args):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)


class RPC:
    def __init__(self, process):
        self.process = process
        self.messages = queue.Queue()
        self.pending = []
        self.identity = 0
        self.reader = threading.Thread(target=self.read, daemon=True)
        self.reader.start()

    def read(self):
        for line in self.process.stdout:
            try:
                self.messages.put(json.loads(line))
            except ValueError:
                pass
        self.messages.put(None)

    def send(self, message):
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()

    def next(self, deadline):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("Codex fixture event deadline")
        try:
            message = self.messages.get(timeout=remaining)
        except queue.Empty as error:
            raise TimeoutError("Codex fixture event deadline") from error
        if message is None:
            raise RuntimeError("Codex exited before fixture completed")
        return message

    def request(self, method, params):
        self.identity += 1
        identity = self.identity
        self.send({"id": identity, "method": method, "params": params})
        deadline = time.monotonic() + 20
        while True:
            message = self.next(deadline)
            if message.get("id") == identity and "method" not in message:
                if "error" in message:
                    raise RuntimeError(message["error"])
                return message["result"]
            self.pending.append(message)

    def turn(self, thread):
        self.request("turn/start", {"threadId": thread, "input": [{"type": "text", "text": "Write only the local fixture marker."}]})
        deadline = time.monotonic() + 20
        approvals = []
        while True:
            message = self.pending.pop(0) if self.pending else self.next(deadline)
            if "id" in message and "method" in message:
                assert message["method"] == "item/commandExecution/requestApproval", "Unexpected client request"
                approvals.append(message["method"])
                self.send({"id": message["id"], "result": {"decision": "decline"}})
            if message.get("method") == "turn/completed":
                return approvals


def verify(cli, root, workspace, fixture):
    env = {key: os.environ[key] for key in ("PATH", "HOME", "TMPDIR", "LANG") if key in os.environ}
    env["CODEX_HOME"] = str(root)
    (root / "lever").write_text("auto")
    with (root / "server-stderr").open("w") as stderr:
        process = subprocess.Popen([cli, "app-server", "--stdio"], cwd=workspace, env=env,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr, text=True, start_new_session=True)
        rpc = RPC(process)
        try:
            rpc.request("initialize", {"clientInfo": {"name": "ahakey-live-approval-fixture", "version": "1"},
                "capabilities": {"experimentalApi": True}})
            config = rpc.request("config/read", {"includeLayers": False})["config"]
            assert config.get("model_provider") == "fixture", "Model provider was overridden"
            assert config.get("model_providers", {}).get("fixture", {}).get("base_url") == fixture.base_url, "Provider is not the loopback fixture"
            assert not config.get("notify") and not config.get("mcp_servers"), "External commands or MCP servers configured"
            catalog = rpc.request("hooks/list", {"cwds": [str(workspace)]})["data"][0]
            assert not catalog["errors"] and len(catalog["hooks"]) == 6
            assert all(hook["trustStatus"] == "trusted" and hook["enabled"] for hook in catalog["hooks"]), "Untrusted hooks cannot prove protection"
            thread = rpc.request("thread/start", {"cwd": str(workspace), "ephemeral": True, "model": "gpt-5.4"})["thread"]["id"]
            results = {}
            for stage in ("auto", "manual", "offline", "paused", "restored"):
                fixture.stage = stage
                (root / "lever").write_text("auto" if stage in ("auto", "paused", "restored") else stage)
                paused = root / "approval-control/codex.paused"
                if stage == "paused":
                    paused.parent.mkdir(exist_ok=True)
                    paused.write_bytes(b"\x01")
                else:
                    paused.unlink(missing_ok=True)
                log = root / "hook-events"
                log.unlink(missing_ok=True)
                before = fixture.requests
                approvals = rpc.turn(thread)
                assert fixture.requests == before + 2, "Turn did not use the two local Responses fixtures"
                events = [json.loads(line) for line in log.read_text().splitlines()]
                pre_tool = [event for event in events if event["event"] == "CodexPreToolUse"]
                assert pre_tool and all(event["mode"] == ("bypassPermissions" if fixture.legacy else "default") for event in pre_tool), events
                automatic = stage in ("auto", "restored")
                marker = (workspace / ("marker-" + stage)).exists()
                assert marker == automatic, (stage, "unexpected tool execution", events)
                if fixture.legacy:
                    assert not approvals, "Old bypass protection denies; it cannot display a native prompt"
                else:
                    assert any(event["event"] == "CodexPermissionRequest" for event in events), events
                    assert bool(approvals) == (not automatic), (stage, approvals)
                assert 'approval_policy = "on-request"' in (root / "config.toml").read_text()
                results[stage] = {"markerExecuted": marker, "nativeApprovals": approvals, "permissionMode": pre_tool[-1]["mode"]}
            return results
        finally:
            terminate_process_group(process)
            process.stdin.close()
            rpc.reader.join(timeout=2)
            process.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", default=shutil.which("codex"))
    parser.add_argument("--legacy-bypass", action="store_true", help="Simulate an already-open old bypass session")
    args = parser.parse_args()
    if not args.cli:
        parser.error("Codex CLI is required")
    version = subprocess.check_output([args.cli, "--version"], text=True, timeout=5).strip()
    source = Path(__file__).resolve().parents[1] / "Sources/Shared"
    with tempfile.TemporaryDirectory(prefix="ahakey-codex-live-", dir="/tmp") as directory:
        root = Path(directory).resolve()  # Trust keys require the canonical path.
        workspace = root / "work"
        workspace.mkdir()
        with LocalResponses(workspace, args.legacy_bypass) as fixture:
            (root / "config.toml").write_text(f'''model = "gpt-5.4"
model_provider = "fixture"
approval_policy = "on-request"
sandbox_mode = "workspace-write"
[features]
hooks = true
[model_providers.fixture]
name = "Local fixture"
base_url = "{fixture.base_url}"
wire_api = "responses"
requires_openai_auth = false
''')
            (root / "main.swift").write_text(SWIFT)
            names = ["CodexConfigLeverSync.swift", "ApprovalAutomationControl.swift", "CursorApprovalPolicySync.swift",
                "KimiConfigPolicySync.swift", "CodexHookTrust.swift", "CodexHookApproval.swift"]
            generator = root / "generate"
            subprocess.run(["swiftc", *[str(source / name) for name in names], str(root / "main.swift"), "-o", str(generator)], check=True, timeout=60)
            agent = root / "agent's space/ahakeyconfig-agent"
            agent.parent.mkdir()
            agent.write_text('#!/bin/sh\nexec "$CODEX_HOME/generate" "$CODEX_HOME" hook "$2"\n')
            agent.chmod(0o700)
            for operation in ("setup", "legacy" if args.legacy_bypass else "baseline"):
                subprocess.run([str(generator), str(root), operation], check=True, timeout=5)
            results = verify(args.cli, root, workspace, fixture)
            print(json.dumps({"cli": version, "legacyBypass": args.legacy_bypass, "outcomes": results,
                "localProviderRequests": fixture.requests,
                "scope": "Production policy/output builders and native CLI; synthetic lever facts, no physical BLE or real provider"}, indent=2))


if __name__ == "__main__":
    main()

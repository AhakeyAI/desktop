#!/usr/bin/env python3
"""Check production-generated hook trust with a local Codex CLI, without user config/auth.

Requires macOS, swiftc and codex. Only temporary fixture hooks execute; the local
model endpoint is intentionally unavailable and UserPromptSubmit blocks the turn.
"""
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import tempfile
import threading
import time


SWIFT_FIXTURE = r'''
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let configURL = root.appendingPathComponent("config.toml")
let mode = CommandLine.arguments[2]
var config = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
if mode == "initial" {
    let command = "/bin/sh " + root.appendingPathComponent("user-hook.sh").path
    let hash = CodexHookTrust.trustedHash(event: "SessionStart", matcher: "", command: command, timeout: 10)!
    let key = CodexHookTrust.stateKey(configPath: configURL.path, event: "SessionStart")!
    config = """
    model = "hook-smoke"
    model_provider = "hook_smoke"
    [model_providers.hook_smoke]
    name = "Local test endpoint"
    base_url = "http://127.0.0.1:1/v1"
    wire_api = "responses"
    requires_openai_auth = false
    [features]
    hooks = true
    [[hooks.SessionStart]]
    matcher = ""
    [[hooks.SessionStart.hooks]]
    type = "command"
    command = "\(command)"
    timeout = 10
    [hooks.state."\(key)"]
    trusted_hash = "\(hash)"
    """
}
if mode == "remove" {
    config = try CodexHookTrust.removingManagedHooks(in: config, configPath: configURL.path)
} else {
    config = try CodexHookTrust.installAgentHooks(in: config, configPath: configURL.path,
        agentBinaryPath: root.appendingPathComponent("test agent's hook.sh").path)
}
try config.write(to: configURL, atomically: true, encoding: .utf8)
'''


def inspect(codex, root, execute=False):
    env = {k: os.environ[k] for k in ("PATH", "HOME", "TMPDIR", "LANG") if k in os.environ}
    env["CODEX_HOME"] = str(root)
    with (root / "server-stderr.log").open("w") as stderr:
        process = subprocess.Popen([codex, "app-server", "--stdio"], cwd=root, env=env,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=stderr, text=True)
        messages = queue.Queue()

        def read_messages():
            for line in process.stdout:
                try:
                    messages.put(json.loads(line))
                except ValueError:
                    continue
            messages.put(None)

        threading.Thread(target=read_messages, daemon=True).start()
        request_id = 0

        def rpc(method, params):
            nonlocal request_id
            request_id += 1
            process.stdin.write(json.dumps(dict(id=request_id, method=method, params=params)) + "\n")
            process.stdin.flush()
            deadline = time.monotonic() + 30
            while True:
                response = messages.get(timeout=max(.1, deadline - time.monotonic()))
                if response is None:
                    raise RuntimeError("Codex exited before responding to " + method)
                if response.get("id") == request_id:
                    if "error" in response:
                        raise RuntimeError(response["error"])
                    return response["result"]
                if time.monotonic() >= deadline:
                    raise TimeoutError(method)

        try:
            rpc("initialize", dict(clientInfo=dict(name="ahakey-hook-verification", version="1"),
                                   capabilities=dict(experimentalApi=True)))
            entry = rpc("hooks/list", dict(cwds=[str(root)]))["data"][0]
            assert not entry["errors"], entry["errors"]
            hooks = entry["hooks"]
            assert all(h["trustStatus"] == "trusted" and h["enabled"] for h in hooks), hooks
            if execute:
                thread = rpc("thread/start", dict(cwd=str(root), ephemeral=True, model="hook-smoke"))
                rpc("turn/start", dict(threadId=thread["thread"]["id"],
                    input=[dict(type="text", text="Blocked local hook smoke test.")]))
                expected = {"user", "CodexSessionStart", "CodexUserPromptSubmit"}
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline:
                    marker = root / "executed"
                    if marker.exists() and expected <= set(marker.read_text().splitlines()):
                        break
                    time.sleep(.05)
                else:
                    raise AssertionError("Codex did not execute all expected fixture hooks")
            return hooks
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            process.stdin.close()
            process.stdout.close()


def main():
    codex = shutil.which("codex")
    if not codex:
        raise SystemExit("codex CLI is required")
    sources = Path(__file__).resolve().parents[1] / "Sources" / "Shared"
    with tempfile.TemporaryDirectory(prefix="ahakey-hook-smoke-") as temporary:
        root = Path(temporary).resolve()
        (root / "main.swift").write_text(SWIFT_FIXTURE)
        generate = root / "generate"
        subprocess.run(["swiftc", str(sources / "CodexConfigLeverSync.swift"),
                        str(sources / "CodexHookTrust.swift"), str(root / "main.swift"),
                        "-o", str(generate)], check=True)
        (root / "user-hook.sh").write_text(
            '#!/bin/sh\ncat >/dev/null\necho user >> "$CODEX_HOME/executed"\nprintf "{}\\n"\n')
        agent = root / "test agent's hook.sh"
        agent.write_text('''#!/bin/sh
cat >/dev/null
printf '%s\n' "$2" >> "$CODEX_HOME/executed"
if [ "$2" = CodexUserPromptSubmit ]; then
    printf '{"decision":"block","reason":"Local hook verification complete"}\n'
else
    printf '{}\n'
fi
''')
        agent.chmod(0o700)
        results = {}
        for mode in ("initial", "reinstall", "remove"):
            subprocess.run([str(generate), str(root), mode], check=True)
            hooks = inspect(codex, root, execute=mode == "initial")
            assert len(hooks) == (1 if mode == "remove" else 7), hooks
            if mode != "remove":
                assert any(h["key"].endswith(":session_start:1:0") for h in hooks)
            results[mode] = dict(hooks=len(hooks), trusted=len(hooks))
        results["executed"] = sorted(set((root / "executed").read_text().splitlines()))
        results["codex"] = subprocess.check_output([codex, "--version"], text=True).strip()
        print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()

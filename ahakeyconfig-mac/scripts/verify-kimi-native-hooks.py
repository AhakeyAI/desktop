#!/usr/bin/env python3
"""Exercise production Kimi hook install/reinstall/remove in a temporary v2 home.

Only fixture scripts run. A retained user hook blocks the prompt before a model
call; the configured provider points at an unavailable loopback endpoint.
This proves lifecycle/config compatibility, not physical or live dial control.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


from hook_lifecycle_fixture import ForbiddenModelEndpoint, policy_swift_sources


SWIFT = r'''
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let mode = CommandLine.arguments[2]
let config = root.appendingPathComponent("config.toml")
let before = try String(contentsOf: config, encoding: .utf8)
let location = KimiConfigPolicySync.location(home: root, environment: ["KIMI_CODE_HOME": root.path], executables: [])
let actual = KimiConfigPolicySync.productionConfigURL
guard actual.resolvingSymlinksInPath() == config.resolvingSymlinksInPath() else {
    FileHandle.standardError.write(Data("Config mismatch: \(actual.path) != \(config.path)\n".utf8)); exit(1)
}
guard KimiConfigPolicySync.apply(auto: true) == .unsupportedRuntime,
      try String(contentsOf: config, encoding: .utf8) == before else {
    FileHandle.standardError.write(Data("Native hook changed unrevocable permissions\n".utf8)); exit(1)
}
let next = mode == "remove" ? try KimiHooksConfiguration.removing(in: before)
    : try KimiHooksConfiguration.installing(in: before, location: location,
        agentPath: root.appendingPathComponent("agent's space/ahakeyconfig-agent").path)
try next.write(to: config, atomically: true, encoding: .utf8)
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", default=shutil.which("kimi"))
    args = parser.parse_args()
    if not args.cli:
        parser.error("a native Kimi v2 CLI is required")
    version = subprocess.check_output([args.cli, "--version"], text=True, timeout=5).strip()
    if not version.startswith("2."):
        parser.error("this fixture targets native Kimi v2; legacy support has separate tests")
    sources = Path(__file__).resolve().parents[1] / "Sources/Shared"
    fixture_sources = policy_swift_sources(sources) + [sources / "KimiHooksConfiguration.swift", sources / "JSONHooksConfiguration.swift"]
    with tempfile.TemporaryDirectory(prefix="ahakey-kimi-lifecycle-") as directory, ForbiddenModelEndpoint() as endpoint:
        root = Path(directory).resolve()
        (root / "main.swift").write_text(SWIFT)
        generator = root / "generate"
        subprocess.run(["swiftc", *map(str, fixture_sources), str(root / "main.swift"), "-o", str(generator)], check=True, timeout=60)
        agent = root / "agent's space/ahakeyconfig-agent"
        agent.parent.mkdir()
        agent.write_text('#!/bin/sh\ncat >/dev/null\nprintf "%s\\n" "$2" >> "$KIMI_CODE_HOME/markers"\nprintf "{}\\n"\n')
        agent.chmod(0o700)
        user = root / "user-hook.sh"
        user.write_text('#!/bin/sh\ncat >/dev/null\nprintf "user\\n" >> "$KIMI_CODE_HOME/markers"\nprintf "AHAKEY_KIMI_FIXTURE_BLOCKED\\n" >&2\nexit 2\n')
        user.chmod(0o700)
        # The user hook remains after AhaKey removal, including its block.
        config = '''default_model = "fixture"
default_permission_mode = "manual"
telemetry = false
auto_session_title = false
[providers.fixture]
type = "openai"
base_url = "http://127.0.0.1:1/v1"
api_key = "offline-fixture-only"
[models.fixture]
provider = "fixture"
model = "fixture"
max_context_size = 32768
[[hooks]]
event = "UserPromptSubmit"
command = ''' + json.dumps(str(user)) + '\ntimeout = 5\n'
        config = config.replace("http://127.0.0.1:1/v1", f"http://127.0.0.1:{endpoint.server.server_port}/v1")
        (root / "config.toml").write_text(config)
        (root / "tui.toml").write_text('[upgrade]\nauto_install = false\n')
        env = {key: os.environ[key] for key in ("PATH", "TMPDIR", "LANG") if key in os.environ}
        env["KIMI_CODE_HOME"] = str(root)
        results = {}
        previous = None
        for stage in ("initial", "reinstall", "remove"):
            subprocess.run([str(generator), str(root), stage], env=env, check=True, timeout=5)
            actual = (root / "config.toml").read_text()
            if stage == "reinstall":
                assert actual == previous, "Reinstall must be idempotent"
            previous = actual
            assert actual.count("[[hooks]]") == (1 if stage == "remove" else 10)
            doctor = subprocess.run([args.cli, "doctor"], env=env, cwd=root, capture_output=True, text=True, timeout=10)
            assert doctor.returncode == 0, "Native configuration schema rejected"
            assert "default_yolo" not in doctor.stdout + doctor.stderr
            marker = root / "markers"
            marker.unlink(missing_ok=True)
            result = subprocess.run([args.cli, "-p", "Blocked local lifecycle fixture."], env=env, cwd=root,
                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=20)
            executed = set(marker.read_text().splitlines()) if marker.exists() else set()
            assert "user" in executed, "Retained user blocking hook did not execute"
            assert result.returncode == 1 and "AHAKEY_KIMI_FIXTURE_BLOCKED" in result.stdout + result.stderr, "CLI did not report the expected hook block"
            assert endpoint.server.calls == 0, "A blocked prompt reached the model endpoint"
            if stage == "remove":
                assert executed == {"user"}, "AhaKey hook survived removal"
            else:
                assert {"KimiSessionStart", "KimiUserPromptSubmit"} <= executed, "Production hook argv did not execute"
            results[stage] = {"configuredHooks": actual.count("[[hooks]]"), "executed": sorted(executed), "cliExit": result.returncode}
        print(json.dumps({"cli": version, "lifecycle": results, "modelRequests": endpoint.server.calls,
            "scope": "temporary home; lifecycle only; no live dial control claimed"}, indent=2))


if __name__ == "__main__":
    main()

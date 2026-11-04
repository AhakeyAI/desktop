"""Run the locally installed consumer function unchanged against the memory Java fixture."""
import argparse
import hashlib
import json
from pathlib import Path
import socket
import struct
import subprocess
import time
import threading
import queue

parser = argparse.ArgumentParser()
parser.add_argument("--root", required=True)
parser.add_argument("--consumer", required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()
root = Path(args.root).resolve()
out = root / "target/wd009-implementation"
source = Path(args.consumer)
text = source.read_text(encoding="utf-8")
function = text[text.index("def _load_ahakey_override_uncached()"):
                text.index("\nclass ApprovalResult:")]
namespace = {"socket": socket, "struct": struct,
             "_AHAKEY_BRIDGE_HOST": "127.0.0.1", "_AHAKEY_BRIDGE_PORT": 0,
             "time": time, "_AHAKEY_APPROVAL_CACHE_TTL_S": 0.35, "_ahakey_cache_at": 0.0, "_ahakey_cache_value": None}
exec(compile(function, str(source) + ":actual-function", "exec"), namespace)
classpath = ";".join(str(root / p) for p in [
    "target/wd009-implementation/classes", "target/wd009-implementation/test-classes",
    "target/WD008-Preview-R6-LocalModel-1.0.17/image/AhaKeyStudio/app/lib/*", "src/main/resources"])
process = subprocess.Popen([
    "D:/jdk-17.0.19.10-hotspot/bin/java.exe", "-Dfile.encoding=UTF-8",
    "-Duser.home=" + str(out / "home"), "-cp", classpath,
    "com.example.ahakey.service.KimiConsumerFixture"], cwd=out,
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    text=True, encoding="utf-8", creationflags=0x08000000)
logs, results = [], []
ready = queue.Queue()
def drain():
    for line in process.stdout:
        logs.append(line)
        if line.startswith("FIXTURE_READY "):
            ready.put(line)
    ready.put(None)
reader = threading.Thread(target=drain, daemon=True)
reader.start()
try:
    for state in [t + "-" + s for t in ["usb", "ble"] for s in ["auto", "manual", "custom", "unknown", "auto", "disconnected", "delayed-auto", "slow-auto", "manual", "auto"]] + ["prepare", "ble-auto", "maintenance"]:
        process.stdin.write(state + "\n")
        process.stdin.flush()
        line = ready.get(timeout=30)
        if line is None:
            raise RuntimeError("Fixture exited before ready")
        namespace["_AHAKEY_BRIDGE_PORT"] = int(line.split()[-1])
        started = time.monotonic()
        actual = namespace["get_ahakey_approval_override"](force_refresh=True)
        elapsed = time.monotonic() - started
        passed = actual is not None and actual["is_auto"] is True if state.endswith("auto") and "slow" not in state else actual is None
        results.append({"state": state, "actual_consumer_result": actual, "elapsed_seconds": elapsed, "pass": passed})
        if "slow" in state: time.sleep(0.6)  # let the isolated timed-out request finish, never reuse its AUTO
    process.stdin.write("quit\n")
    process.stdin.flush()
    process.wait(timeout=10)
    reader.join(timeout=5)
finally:
    if process.poll() is None:
        process.terminate()  # Only this fixture child, never an application or bridge process.
        process.wait(timeout=5)
report = {"consumer_path": str(source), "consumer_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
          "function_sha256": hashlib.sha256(function.encode()).hexdigest(), "fixture_exit": process.returncode,
          "transport": "actual consumer force_refresh -> loopback Java Kimi bridge -> actual BleManager status/97/parser via memory USB or framed BLE wire; C# radio/hardware not exercised",
          "results": results}
destination = Path(args.output)
destination.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
destination.with_suffix(".log").write_text("".join(logs), encoding="utf-8")
print(json.dumps(report, ensure_ascii=False, indent=2))
assert process.returncode == 0 and all(r["pass"] for r in results)

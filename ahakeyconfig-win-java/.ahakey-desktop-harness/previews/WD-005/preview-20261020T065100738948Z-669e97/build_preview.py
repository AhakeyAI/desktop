"""Token-local build evidence helper; never launches the application."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime, timezone

TOKEN = Path(__file__).resolve().parent
ROOT = TOKEN.parents[3]
SOURCE = TOKEN / "source"
RUNTIME = TOKEN / "runtime-jar-classpath"
JDK = Path("D:/jdk-17.0.19.10-hotspot")
MAVEN = Path("C:/Program Files/apache-maven-3.9.12/bin/mvn.cmd")
sys.path.insert(0, str(ROOT / ".agents/skills/ahakey-desktop-harness/scripts"))
import desktop as harness


def save(name, data):
    with (TOKEN / name).open("x", encoding="utf-8") as stream:
        json.dump(data, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def fingerprints(name):
    start = harness.read_json(TOKEN / "START.json")
    change = harness.change(ROOT, "WD-005")
    result = {
        "at": datetime.now(timezone.utc).isoformat(),
        "workspace": harness.source_fingerprint(ROOT),
        "snapshot": harness.source_fingerprint(SOURCE),
        "approval": harness.approval_ok(ROOT, change),
        "state_sha256": sha(ROOT / ".ahakey-desktop-harness/STATE.json"),
        "head": subprocess.check_output(
            ["git", "--no-optional-locks", "rev-parse", "HEAD"],
            cwd=ROOT, text=True
        ).strip(),
    }
    save(name, result)
    assert start["status"] == "build_authorized"
    assert change["build_round"] == start["build_round"] == 7
    assert result["workspace"]["sha256"] == start["working_code_fingerprint"]
    assert result["snapshot"]["sha256"] == start["snapshot_fingerprint"]
    assert result["approval"] == start["approval_sha256"]
    return result


def build():
    fingerprints("FINGERPRINT_BEFORE.json")
    assert not (SOURCE / "target").exists(), "Existing target needs review"
    env = dict(os.environ)
    env["JAVA_HOME"] = str(JDK)
    env["MAVEN_OPTS"] = "-Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8"
    records = []
    commands = [
        ("java-version", [str(JDK / "bin/java.exe"), "-version"]),
        ("maven-version", [str(MAVEN), "-version"]),
        ("package", [str(MAVEN), "-o", "-Dmaven.repo.local=" + str(ROOT / ".m2repo"),
                     "--batch-mode", "--no-transfer-progress", "package", "-DskipTests"]),
    ]
    for label, args in commands:
        with (TOKEN / (label + ".stdout.log")).open("xb") as out:
            with (TOKEN / (label + ".stderr.log")).open("xb") as err:
                started = datetime.now(timezone.utc).isoformat()
                p = subprocess.run(args, cwd=SOURCE, env=env, stdout=out, stderr=err)
        records.append({
            "name": label, "argv": args, "command": subprocess.list2cmdline(args),
            "cwd": str(SOURCE), "started": started,
            "finished": datetime.now(timezone.utc).isoformat(), "exit_code": p.returncode,
            "JAVA_HOME": env["JAVA_HOME"], "MAVEN_OPTS": env["MAVEN_OPTS"],
        })
        print(label, "exit", p.returncode, flush=True)
        if p.returncode:
            break
    save("BUILD_EXECUTION.json", records)
    fingerprints("FINGERPRINT_AFTER_BUILD.json")
    assert len(records) == 3 and all(x["exit_code"] == 0 for x in records), "Build failed"


def inspect():
    execution = json.loads((TOKEN / "BUILD_EXECUTION.json").read_text(encoding="utf-8"))
    assert execution[-1]["name"] == "package" and execution[-1]["exit_code"] == 0
    RUNTIME.mkdir(exist_ok=False)
    jar = SOURCE / "target/ahakey-studio-1.0.0.jar"
    shutil.copy2(jar, RUNTIME / jar.name)
    shutil.copytree(SOURCE / "target/lib", RUNTIME / "lib")
    files = {}
    for file in sorted(RUNTIME.rglob("*")):
        if file.is_file():
            relative = file.relative_to(RUNTIME).as_posix()
            source = SOURCE / "target" / relative
            assert sha(file) == sha(source)
            files[relative] = {"bytes": file.stat().st_size, "sha256": sha(file),
                               "source": str(source)}
    native = {}
    for file in sorted((RUNTIME / "lib").glob("*.jar")):
        with zipfile.ZipFile(file) as archive:
            native[file.name] = [x for x in archive.namelist()
                                 if x.lower().endswith((".dll", ".so", ".dylib"))]
    with zipfile.ZipFile(RUNTIME / jar.name) as archive:
        entries = set(archive.namelist())
        classes = ["Main", "App", "service/BleManager", "service/DisplayConfigService",
                   "service/OledUploadService", "service/AiRuntimeDisplayService"]
        versions = {}
        for name in classes:
            data = archive.read("com/example/ahakey/" + name + ".class")
            assert data[:4] == b"\xca\xfe\xba\xbe"
            versions[name] = int.from_bytes(data[6:8], "big")
            assert versions[name] == 61
        resources = []
        for file in sorted((SOURCE / "src/main/resources").rglob("*")):
            if file.is_file():
                name = file.relative_to(SOURCE / "src/main/resources").as_posix()
                assert archive.read(name) == file.read_bytes(), "Resource mismatch: " + name
                resources.append(name)
        assert not any(x.startswith("com/example/ahakey/displayconfig/") for x in entries)
        manifest = archive.read("META-INF/MANIFEST.MF").decode("utf-8")
    for name in ("base", "controls", "fxml", "graphics"):
        assert "javafx-" + name + "-17.0.10-win.jar" in native
    assert any(x.endswith(".dll") for x in native["javafx-graphics-17.0.10-win.jar"])
    save("STATIC_INSPECTION.json", {
        "class_major_versions": versions, "resources_byte_identical": resources,
        "native_entries": native, "jar_manifest": manifest,
        "tests_not_in_main_jar": True, "copied_only_snapshot_target": True,
        "application_started": False,
    })
    save("ARTIFACT_MANIFEST.json", {"root": str(RUNTIME), "files": files})
    after = fingerprints("FINGERPRINT_AFTER_COPY.json")
    before = json.loads((TOKEN / "FINGERPRINT_BEFORE.json").read_text(encoding="utf-8"))
    assert before["state_sha256"] == after["state_sha256"]
    assert before["head"] == after["head"]
    print("Static inspection passed:", len(files), "files;", len(resources), "resources")
    print("Main JAR SHA256:", files[jar.name]["sha256"])


if __name__ == "__main__":
    {"build": build, "inspect": inspect}[sys.argv[1]]()

#!/usr/bin/env python3
"""U1/U1R3 gate: user-facing copy must not keep BLE-owner phrasing or bare Agent.

Scans production Views, actual user error/status sources (including
AhaKeyAgent.swift), the localization generator, and both .strings catalogs.
Legacy technical identity may appear only as an exact allowlisted diagnostic
string that already contains 「兼容标识」 / "Compatibility IDs". Third-party
Cursor Agent product names with explicit Cursor context are not treated as
AhaKey Runtime identity.
"""
from __future__ import annotations

import argparse
import ast
import shutil
import sys
import tempfile
from pathlib import Path
import re

FORBIDDEN_PHRASES = [
    "控制方",
    "临时接管蓝牙",
    "接管蓝牙",
    "接管 BLE",
    "自占 BLE",
    "临时由 AhaKey Studio",
    "交还给 Agent",
    "由 Agent 占用",
    "设备信息 · Agent",
    "将蓝牙交给",
    "把蓝牙交给",
    "交给 Agent",
    "Agent 占用",
    "Agent 将接管",
    "Device Info · Agent",
    "Device info · Agent",
    "taking over BLE",
    "takes over BLE",
    "taken over by AhaKey Studio",
    "temporarily taken over",
    "hand Bluetooth back",
    "Occupied by Agent",
    "Used by Agent",
]

# Whole-string allowlist only. Do not treat 「兼容标识」 as a line-level skip.
ALLOWED_DIAGNOSTIC_STRINGS = {
    "请确认 AhaKey Runtime 在跑并已连上键盘。（兼容标识：LaunchAgent / ahakeyconfig-agent）\n",
    "Confirm AhaKey Runtime is running and the keyboard is connected. (Compatibility IDs: LaunchAgent / ahakeyconfig-agent)\n",
    """
                打开「权限诊断」可以看到后台服务自检结果。兼容标识：LaunchAgent label 仍为 lab.jawa.ahakeyconfig.agent，可执行文件仍为 ahakeyconfig-agent。
                • 后台服务已注册：login item 装好
                • 进程在跑：launchd 已拉起后台服务
                • Hook 已配置：Claude/Cursor/Codex/Kimi 的 .json / settings 都加好了 ahakey-hook 引用
                """,
    """
                Open Permission Diagnostics for background-service self-check. Compatibility IDs: LaunchAgent label remains lab.jawa.ahakeyconfig.agent; executable remains ahakeyconfig-agent.
                • Background service registered: login item installed
                • Process running: launchd started the background service
                • Hooks configured: Claude/Cursor/Codex/Kimi settings include ahakey-hook
                """,
    "AhaKey Runtime 主日志（兼容标识：ahakeyconfig-agent）",
    "AhaKey Runtime main log (Compatibility IDs: ahakeyconfig-agent)",
}

ALLOWED_NORMALIZED = {item.strip() for item in ALLOWED_DIAGNOSTIC_STRINGS}

IDENTITY_RE = re.compile(
    r"(?<![A-Za-z])Agent(?![A-Za-z])"
    r"|LaunchAgent"
    r"|ahakeyconfig-agent"
    r"|lab\.jawa\.ahakeyconfig\.agent"
)

# Cursor's own product surface, not AhaKey Runtime.
CURSOR_PRODUCT_IDENTITY_RE = re.compile(
    r"Cursor(?:\s+Composer)?\s*/\s*Agent|Cursor Agent"
)

NSLOCALIZED_RE = re.compile(
    r"NSLocalizedString\(\s*(?:\"\"\"(.*?)\"\"\"|\"((?:[^\"\\]|\\.)*)\")",
    re.DOTALL,
)

UI_LITERAL_RE = re.compile(
    r"(?:(?:SwiftUI\.)?(?:Text|Button|Label|Toggle|Section))\(\s*(?:verbatim:\s*)?(?:\"\"\"(.*?)\"\"\"|\"((?:[^\"\\]|\\.)*)\")"
    r"|\.(?:help|alert|navigationTitle|confirmationDialog)\(\s*(?:\"\"\"(.*?)\"\"\"|\"((?:[^\"\\]|\\.)*)\")",
    re.DOTALL,
)

PROMPT_ASSIGN_RE = re.compile(
    r"\b\w*(?:Status|Alert|Message)\w*\s*=\s*(?:\"\"\"(.*?)\"\"\"|\"((?:[^\"\\]|\\.)*)\")",
    re.DOTALL,
)

STRINGS_ENTRY_RE = re.compile(
    r"\"((?:[^\"\\]|\\.)*)\"\s*=\s*\"((?:[^\"\\]|\\.)*)\"\s*;"
)

SWIFT_RELATIVE = [
    "Sources/Views",
    "Sources/Models/AhaKeyStudioRuntimeStore.swift",
    "Sources/Models/AhaKeyStudioModels.swift",
    "Sources/Utilities/RuntimeServiceManager.swift",
    "Sources/Agent/HookSupport.swift",
    "Sources/Agent/AhaKeyAgent.swift",
]

SCAN_RELATIVE_FILES = [
    "scripts/generate_localizations.py",
    "Resources/zh-Hans.lproj/Localizable.strings",
    "Resources/en.lproj/Localizable.strings",
]

MUTATIONS = {
    "view-text-verbatim": {
        "rel": "Sources/Views/DeviceInfoView.swift",
        "old": 'Text(NSLocalizedString("诊断日志", comment: ""))',
        "new": 'Text(verbatim: "控制方")',
        "phrase": "控制方",
    },
    "status-message": {
        "rel": "Sources/Views/AhaKeyStudioView.swift",
        "old": 'syncStatusMessage = NSLocalizedString("键盘连接始终由 AhaKey Runtime 管理。", comment: "")',
        "new": 'syncStatusMessage = "控制方"',
        "phrase": "控制方",
    },
    "catalog-studio-takeover": {
        "rel": "scripts/generate_localizations.py",
        "old": '    "主键": "Main Key",\n',
        "new": (
            '    "临时由 AhaKey Studio 接管蓝牙，用于改键、LCD、同步和本机灯效测试。": '
            '"Bluetooth is temporarily taken over by AhaKey Studio.",\n'
        ),
        "phrase": "接管蓝牙",
    },
    "agent-status": {
        "rel": "Sources/Agent/AhaKeyAgent.swift",
        "old": 'emit(NSLocalizedString("蓝牙就绪", comment: ""))',
        "new": 'emit(NSLocalizedString("临时由 AhaKey Studio 接管蓝牙", comment: ""))',
        "phrase": "接管蓝牙",
    },
}


def unescape_swift_or_c(raw: str) -> str:
    return (
        raw.replace(r"\\", "\0")
        .replace(r"\"", '"')
        .replace(r"\n", "\n")
        .replace(r"\t", "\t")
        .replace("\0", "\\")
    )


def is_allowed(text: str) -> bool:
    return text.strip() in ALLOWED_NORMALIZED


def decode_path(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
        return raw.decode("utf-16")
    return raw.decode("utf-8")


def iter_swift_user_strings(text: str) -> list[str]:
    found: list[str] = []
    for match in NSLOCALIZED_RE.finditer(text):
        triple, quoted = match.group(1), match.group(2)
        if triple is not None:
            found.append(triple)
        elif quoted is not None:
            found.append(unescape_swift_or_c(quoted))
    for match in UI_LITERAL_RE.finditer(text):
        for group in match.groups():
            if group is None:
                continue
            found.append(group if '"""' in match.group(0) else unescape_swift_or_c(group))
    for match in PROMPT_ASSIGN_RE.finditer(text):
        triple, quoted = match.group(1), match.group(2)
        if triple is not None:
            found.append(triple)
        elif quoted is not None:
            found.append(unescape_swift_or_c(quoted))
    return found


def iter_translations(path: Path) -> list[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    mapping: dict[str, str] | None = None
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "TRANSLATIONS":
                    mapping = ast.literal_eval(node.value)
    if mapping is None:
        raise RuntimeError(f"TRANSLATIONS dict not found in {path}")
    texts: list[str] = []
    for key, value in mapping.items():
        texts.append(key)
        texts.append(value)
    return texts


def iter_strings_file(path: Path) -> list[str]:
    text = decode_path(path)
    found: list[str] = []
    for match in STRINGS_ENTRY_RE.finditer(text):
        found.append(unescape_swift_or_c(match.group(1)))
        found.append(unescape_swift_or_c(match.group(2)))
    return found


def masked_identity_text(text: str) -> str:
    return CURSOR_PRODUCT_IDENTITY_RE.sub("", text)


def check_text(origin: str, text: str, hits: list[str]) -> None:
    if is_allowed(text):
        return
    for phrase in FORBIDDEN_PHRASES:
        if phrase in text:
            hits.append(f"{origin}: forbidden phrase {phrase!r}")
    identity = IDENTITY_RE.search(masked_identity_text(text))
    if identity:
        hits.append(f"{origin}: bare identity {identity.group(0)!r}")


def collect_swift_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for rel in SWIFT_RELATIVE:
        path = root / rel
        if path.is_dir():
            files.extend(sorted(path.glob("*.swift")))
        else:
            files.append(path)
    return files


def scan_root(root: Path) -> list[str]:
    hits: list[str] = []
    for path in collect_swift_files(root):
        rel = path.relative_to(root).as_posix()
        for index, extracted in enumerate(iter_swift_user_strings(decode_path(path)), 1):
            check_text(f"{rel} userString#{index}", extracted, hits)
    generator = root / "scripts/generate_localizations.py"
    for index, extracted in enumerate(iter_translations(generator), 1):
        check_text(f"scripts/generate_localizations.py TRANSLATIONS#{index}", extracted, hits)
    for rel in (
        "Resources/zh-Hans.lproj/Localizable.strings",
        "Resources/en.lproj/Localizable.strings",
    ):
        for index, extracted in enumerate(iter_strings_file(root / rel), 1):
            check_text(f"{rel}#{index}", extracted, hits)
    return hits


def report(hits: list[str]) -> int:
    if hits:
        print("U1 user-facing copy gate failed:", file=sys.stderr)
        for hit in hits:
            print(f"  {hit}", file=sys.stderr)
        return 1
    print("U1 user-facing copy gate ok")
    return 0


def copy_production_tree(src_root: Path, dest_root: Path) -> None:
    for rel in SWIFT_RELATIVE:
        src = src_root / rel
        dest = dest_root / rel
        if src.is_dir():
            shutil.copytree(src, dest)
        else:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)
    for rel in SCAN_RELATIVE_FILES:
        src = src_root / rel
        dest = dest_root / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)


def apply_mutation(root: Path, kind: str) -> Path:
    spec = MUTATIONS[kind]
    path = root / spec["rel"]
    original = path.read_text(encoding="utf-8")
    old, new = spec["old"], spec["new"]
    count = original.count(old)
    if count != 1:
        raise RuntimeError(
            f"mutation {kind} expected unique snippet in {spec['rel']}, found {count}"
        )
    path.write_text(original.replace(old, new, 1), encoding="utf-8")
    return path


def targeted_hits(hits: list[str], rel: str, phrase: str) -> list[str]:
    marker = f"forbidden phrase {phrase!r}"
    return [hit for hit in hits if rel in hit and marker in hit]


def run_mutation(src_root: Path, kind: str) -> int:
    if kind not in MUTATIONS:
        raise SystemExit(f"unknown mutation {kind!r}; choose from {sorted(MUTATIONS)}")
    spec = MUTATIONS[kind]
    rel = spec["rel"]
    phrase = spec["phrase"]
    with tempfile.TemporaryDirectory(prefix="u1-copy-gate-") as tmp:
        dest = Path(tmp)
        copy_production_tree(src_root, dest)
        apply_mutation(dest, kind)
        hits = scan_root(dest)
        matched = targeted_hits(hits, rel, phrase)
        if not matched:
            print(
                f"U1 user-facing copy gate false-green: mutation {kind} did not hit {rel} with {phrase!r}",
                file=sys.stderr,
            )
            for hit in hits:
                print(f"  {hit}", file=sys.stderr)
            return 1
        print(f"U1 user-facing copy gate mutation {kind} detected:")
        print(f"  target: {rel}")
        print(f"  phrase: {phrase}")
        for hit in matched:
            print(f"  {hit}")
        return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=Path,
        default=None,
        help="ahakeyconfig-mac root; defaults to the directory that contains this script",
    )
    parser.add_argument(
        "--snippet",
        help="scan a virtual Swift fragment instead of the production tree",
    )
    parser.add_argument(
        "--mutation",
        choices=sorted(MUTATIONS),
        help="copy the production scan tree, apply a known-bad mutation, and require the full --root scan to fail",
    )
    args = parser.parse_args(argv)
    src_root = args.root.resolve() if args.root else Path(__file__).resolve().parents[1]

    if args.mutation:
        return run_mutation(src_root, args.mutation)

    if args.snippet is not None:
        hits: list[str] = []
        for index, extracted in enumerate(iter_swift_user_strings(args.snippet), 1):
            check_text(f"<snippet> userString#{index}", extracted, hits)
        return report(hits)

    return report(scan_root(src_root))


if __name__ == "__main__":
    raise SystemExit(main())

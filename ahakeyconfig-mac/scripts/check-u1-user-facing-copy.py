#!/usr/bin/env python3
"""U1/U1R1 gate: user-facing copy must not keep BLE-owner phrasing or bare Agent.

Scans production Views, actual user error/status sources, the localization
generator, and both .strings catalogs. Legacy technical identity may appear
only as an exact allowlisted diagnostic string that already contains
「兼容标识」 / "Compatibility IDs". A compatibility marker on any other line
does not blanket-allow forbidden copy.
"""
from __future__ import annotations

import argparse
import ast
import re
import sys
from pathlib import Path

FORBIDDEN_PHRASES = [
    "控制方",
    "临时接管蓝牙",
    "接管 BLE",
    "自占 BLE",
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

NSLOCALIZED_RE = re.compile(
    r"NSLocalizedString\(\s*(?:\"\"\"(.*?)\"\"\"|\"((?:[^\"\\]|\\.)*)\")",
    re.DOTALL,
)

STRINGS_ENTRY_RE = re.compile(
    r"\"((?:[^\"\\]|\\.)*)\"\s*=\s*\"((?:[^\"\\]|\\.)*)\"\s*;"
)

SWIFT_RELATIVE = [
    "Sources/Views",
    "Sources/Models/AhaKeyStudioRuntimeStore.swift",
    "Sources/Models/AhaKeyStudioModels.swift",
    "Sources/Utilities/AgentManager.swift",
    "Sources/Agent/HookSupport.swift",
]


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


def check_text(origin: str, text: str, hits: list[str]) -> None:
    if is_allowed(text):
        return
    for phrase in FORBIDDEN_PHRASES:
        if phrase in text:
            hits.append(f"{origin}: forbidden phrase {phrase!r}")
    identity = IDENTITY_RE.search(text)
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
            check_text(f"{rel} NSLocalizedString#{index}", extracted, hits)
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
    args = parser.parse_args(argv)

    if args.snippet is not None:
        hits: list[str] = []
        for index, extracted in enumerate(iter_swift_user_strings(args.snippet), 1):
            check_text(f"<snippet> NSLocalizedString#{index}", extracted, hits)
        if hits:
            print("U1 user-facing copy gate failed:", file=sys.stderr)
            for hit in hits:
                print(f"  {hit}", file=sys.stderr)
            return 1
        print("U1 user-facing copy gate ok")
        return 0

    root = args.root.resolve() if args.root else Path(__file__).resolve().parents[1]
    hits = scan_root(root)
    if hits:
        print("U1 user-facing copy gate failed:", file=sys.stderr)
        for hit in hits:
            print(f"  {hit}", file=sys.stderr)
        return 1
    print("U1 user-facing copy gate ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

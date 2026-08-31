#!/usr/bin/env python3
"""U1 gate: forbidden legacy BLE-owner / Agent copy in user-facing View + strings.

Old phrases may only appear on a line that also contains the explicit
compatibility marker 兼容标识 (or English "Compatibility IDs").
"""
from __future__ import annotations

import sys
from pathlib import Path

FORBIDDEN = [
    "控制方",
    "临时接管蓝牙",
    "交还给 Agent",
    "由 Agent 占用",
    "设备信息 · Agent",
    "Device Info · Agent",
    "Device info · Agent",
    "hand Bluetooth back to Agent",
    "Occupied by Agent",
    "Used by Agent",
]

ALLOW_MARKERS = ("兼容标识", "Compatibility IDs")

SCAN_RELATIVE = [
    "Sources/Views/AhaKeyStudioView.swift",
    "Sources/Views/DeviceInfoView.swift",
    "Sources/Views/ContentView.swift",
    "Resources/zh-Hans.lproj/Localizable.strings",
    "Resources/en.lproj/Localizable.strings",
]


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    hits: list[str] = []
    for rel in SCAN_RELATIVE:
        path = root / rel
        raw = path.read_bytes()
        if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
            text = raw.decode("utf-16")
        else:
            text = raw.decode("utf-8")
        for i, line in enumerate(text.splitlines(), 1):
            if any(m in line for m in ALLOW_MARKERS):
                continue
            for phrase in FORBIDDEN:
                if phrase in line:
                    hits.append(f"{rel}:{i}: {phrase}")
    if hits:
        print("U1 user-facing copy gate failed:", file=sys.stderr)
        for h in hits:
            print(f"  {h}", file=sys.stderr)
        return 1
    print("U1 user-facing copy gate ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

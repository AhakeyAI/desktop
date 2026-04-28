#!/usr/bin/env python3
"""Generate a macOS .icns app icon from the project ICO."""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image


ICON_SPECS = (
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
)


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    source = root / "VibeCodeKeyboard.ico"
    target = root / "assets" / "macos" / "VibeCodeKeyboard.icns"

    if not source.is_file():
        print(f"Source icon not found: {source}", file=sys.stderr)
        return 1

    target.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="vibekeyboard-iconset-") as tmpdir:
        iconset_dir = Path(tmpdir) / "VibeCodeKeyboard.iconset"
        iconset_dir.mkdir(parents=True, exist_ok=True)

        with Image.open(source) as image:
            rgba = image.convert("RGBA")
            for filename, size in ICON_SPECS:
                resized = rgba.resize((size, size), Image.Resampling.LANCZOS)
                resized.save(iconset_dir / filename, format="PNG")

        cmd = [
            "iconutil",
            "-c",
            "icns",
            str(iconset_dir),
            "-o",
            str(target),
        ]
        subprocess.run(cmd, check=True)

    print(target)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

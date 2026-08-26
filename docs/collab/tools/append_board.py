#!/usr/bin/env python3
"""Append-only writer for docs/collab/board.md.

Always opens the file in append mode (never truncates). Prefer this over
shell redirection such as `>` or write-whole-file editors.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--repo",
        default=str(Path(__file__).resolve().parents[3]),
    )
    parser.add_argument(
        "text",
        nargs="?",
        help="entry text; if omitted, read stdin",
    )
    args = parser.parse_args()
    board = Path(args.repo).resolve() / "docs" / "collab" / "board.md"
    payload = args.text if args.text is not None else sys.stdin.read()
    if not payload.endswith("\n"):
        payload += "\n"
    if not payload.startswith("\n"):
        payload = "\n" + payload
    with board.open("a", encoding="utf-8") as handle:
        handle.write(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Snapshot docs/collab/board.md on every change; restore on catastrophic shrink.

Idle uses macOS kqueue (no polling). Snapshots live in docs/collab/backups/ and
are gitignored. board.md remains the communication source of truth.

Restore rule: if the live file shrinks to less than half of the last good
snapshot and that snapshot is at least 4 KiB, copy the truncated bytes aside
and restore the last good snapshot.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import select
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path


WATCH_FLAGS = (
    select.KQ_NOTE_WRITE
    | select.KQ_NOTE_EXTEND
    | select.KQ_NOTE_RENAME
    | select.KQ_NOTE_DELETE
    | select.KQ_NOTE_ATTRIB
)

MIN_RESTORE_SNAPSHOT_BYTES = 4096
SHRINK_RATIO = 0.5
KEEP_SNAPSHOTS = 80
KEEP_TRUNCATED = 20


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_state(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(value, dict):
            return value
    except (FileNotFoundError, OSError, ValueError, TypeError, json.JSONDecodeError):
        pass
    return {}


def save_state(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + f".tmp.{os.getpid()}")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def stamp() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def snapshot_path(backup_dir: Path, kind: str, size: int, digest: str) -> Path:
    short = digest[:12]
    return backup_dir / f"board-{kind}-{stamp()}-{size}b-{short}.md"


def prune(backup_dir: Path) -> None:
    snapshots = sorted(backup_dir.glob("board-snap-*.md"))
    truncated = sorted(backup_dir.glob("board-TRUNCATED-*.md"))
    for stale in snapshots[:-KEEP_SNAPSHOTS]:
        stale.unlink(missing_ok=True)
    for stale in truncated[:-KEEP_TRUNCATED]:
        stale.unlink(missing_ok=True)


def write_snapshot(backup_dir: Path, kind: str, data: bytes, digest: str) -> Path:
    backup_dir.mkdir(parents=True, exist_ok=True)
    target = snapshot_path(backup_dir, kind, len(data), digest)
    temporary = target.with_suffix(target.suffix + f".tmp.{os.getpid()}")
    temporary.write_bytes(data)
    os.replace(temporary, target)
    prune(backup_dir)
    return target


def latest_good(state: dict, backup_dir: Path) -> Path | None:
    raw = state.get("lastGoodSnapshot")
    if not raw:
        return None
    path = Path(raw)
    if not path.is_file():
        matches = sorted(backup_dir.glob("board-snap-*.md"))
        return matches[-1] if matches else None
    return path


def open_board(board: Path) -> int:
    while True:
        try:
            return os.open(board, os.O_RDONLY)
        except FileNotFoundError:
            time.sleep(0.2)


def process(board: Path, backup_dir: Path, state_path: Path, restore: bool) -> str:
    data = board.read_bytes()
    digest = sha256_bytes(data)
    state = load_state(state_path)
    if digest == state.get("lastDigest"):
        return "unchanged"

    last_good = latest_good(state, backup_dir)
    last_good_size = int(state.get("lastGoodSize") or 0)
    if last_good and last_good.is_file():
        last_good_size = max(last_good_size, last_good.stat().st_size)

    looks_truncated = (
        last_good_size >= MIN_RESTORE_SNAPSHOT_BYTES
        and len(data) < last_good_size * SHRINK_RATIO
    )
    catastrophic = restore and looks_truncated
    if catastrophic and last_good is not None:
        truncated = write_snapshot(backup_dir, "TRUNCATED", data, digest)
        restored = last_good.read_bytes()
        temporary = board.with_suffix(board.suffix + f".restore.{os.getpid()}")
        temporary.write_bytes(restored)
        os.replace(temporary, board)
        restored_digest = sha256_bytes(restored)
        save_state(
            state_path,
            {
                "board": str(board),
                "lastDigest": restored_digest,
                "lastGoodSize": len(restored),
                "lastGoodSnapshot": str(last_good),
                "lastTruncated": str(truncated),
            },
        )
        print(
            f"BOARD_BACKUP_RESTORED from={last_good} truncated={truncated} "
            f"live_bytes={len(data)} restored_bytes={len(restored)}",
            flush=True,
        )
        return "restored"

    kind = "TRUNCATED" if looks_truncated else "snap"
    snap = write_snapshot(backup_dir, kind, data, digest)
    keep_as_good = (not looks_truncated) or last_good is None
    payload = {
        "board": str(board),
        "lastDigest": digest,
        "lastGoodSize": len(data) if keep_as_good else last_good_size,
        "lastGoodSnapshot": str(snap) if keep_as_good else str(last_good),
    }
    if looks_truncated:
        payload["lastTruncated"] = str(snap)
    save_state(state_path, payload)
    print(
        f"BOARD_BACKUP_SAVED {snap} bytes={len(data)}"
        + (" (not last-good; file looks truncated)" if looks_truncated else ""),
        flush=True,
    )
    return "saved"


def watch(board: Path, backup_dir: Path, state_path: Path, restore: bool) -> int:
    process(board, backup_dir, state_path, restore=restore)
    descriptor = open_board(board)
    queue = select.kqueue()

    def register() -> None:
        queue.control(
            [
                select.kevent(
                    descriptor,
                    filter=select.KQ_FILTER_VNODE,
                    flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                    fflags=WATCH_FLAGS,
                )
            ],
            0,
            0,
        )

    register()
    print(f"BOARD_BACKUP_WATCH_READY board={board} backups={backup_dir}", flush=True)
    try:
        while True:
            event = queue.control(None, 1, None)[0]
            if event.fflags & (select.KQ_NOTE_RENAME | select.KQ_NOTE_DELETE):
                os.close(descriptor)
                descriptor = open_board(board)
                register()
            time.sleep(0.15)
            process(board, backup_dir, state_path, restore=restore)
    except KeyboardInterrupt:
        return 0
    finally:
        os.close(descriptor)
        queue.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--repo",
        default=str(Path(__file__).resolve().parents[3]),
        help="repository root",
    )
    parser.add_argument("--once", action="store_true", help="snapshot once and exit")
    parser.add_argument(
        "--no-restore",
        action="store_true",
        help="snapshot only; do not restore on shrink",
    )
    args = parser.parse_args()
    repo = Path(args.repo).resolve()
    board = repo / "docs" / "collab" / "board.md"
    backup_dir = repo / "docs" / "collab" / "backups"
    state_path = backup_dir / ".backup-state.json"
    if not board.is_file():
        print(f"board not found: {board}", file=sys.stderr)
        return 2
    if args.once:
        process(board, backup_dir, state_path, restore=False)
        return 0
    return watch(board, backup_dir, state_path, restore=not args.no_restore)


if __name__ == "__main__":
    raise SystemExit(main())

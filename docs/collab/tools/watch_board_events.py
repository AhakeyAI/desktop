#!/usr/bin/env python3
"""Wake the active Cursor coordinator when Kimi requests a Codex reply.

The board remains the durable source of truth. This process only turns a
filesystem append into a low-latency wake notification for the current Cursor
session. It uses macOS kqueue, so idle operation does not poll or invoke a
model.
"""

from __future__ import annotations

import hashlib
import json
import os
import select
import sys
import time
from pathlib import Path


SENTINEL = "AGENT_LOOP_WAKE_collab-event"
WATCH_FLAGS = (
    select.KQ_NOTE_WRITE
    | select.KQ_NOTE_EXTEND
    | select.KQ_NOTE_RENAME
    | select.KQ_NOTE_DELETE
)


def load_state(path: Path, board: Path) -> tuple[int, str]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        if value.get("board") == str(board):
            return max(0, int(value.get("offset", 0))), str(
                value.get("lastEventDigest", "")
            )
    except (FileNotFoundError, OSError, ValueError, TypeError, json.JSONDecodeError):
        pass
    return board.stat().st_size, ""


def save_state(path: Path, board: Path, offset: int, digest: str) -> None:
    payload = {
        "board": str(board),
        "offset": offset,
        "lastEventDigest": digest,
    }
    # A stale/restarting watcher may briefly overlap this process. Use a
    # process-unique temporary path so concurrent atomic saves cannot steal
    # each other's rename source.
    temporary = path.with_suffix(path.suffix + f".tmp.{os.getpid()}")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, sort_keys=True),
        encoding="utf-8",
    )
    os.replace(temporary, path)


def newest_message(text: str) -> str:
    marker = "\n### ["
    position = text.rfind(marker)
    if position >= 0:
        return text[position + 1 :]
    if text.startswith("### ["):
        return text
    return ""


def should_wake(message: str) -> bool:
    if not message or "Kimi →" not in message:
        return False
    return (
        "需要回复：是" in message
        and ("@Codex" in message or "@Cursor" in message)
    )


def emit_wake(message: str) -> str:
    digest = hashlib.sha256(message.encode("utf-8")).hexdigest()
    heading = message.splitlines()[0] if message else "Kimi board event"
    payload = {
        "prompt": (
            "Kimi 已在 docs/collab/board.md 追加需要 Codex/Cursor 回复的事件。"
            "立即读取 board.md EOF、相关任务卡和 queue；先 ACK，再按完成定义"
            "执行 owner 工作或只读验收/裁决。不要依赖聊天转述，严格遵守任务卡白名单。"
        ),
        "event": heading,
        "digest": digest,
    }
    print(
        f"{SENTINEL} {json.dumps(payload, ensure_ascii=False, separators=(',', ':'))}",
        flush=True,
    )
    return digest


def open_board(board: Path) -> tuple[int, int]:
    while True:
        try:
            descriptor = os.open(board, os.O_RDONLY)
            return descriptor, os.fstat(descriptor).st_size
        except FileNotFoundError:
            time.sleep(0.2)


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(
            "usage: watch_board_events.py BOARD_PATH [STATE_PATH]",
            file=sys.stderr,
        )
        return 2

    board = Path(sys.argv[1]).resolve()
    state = (
        Path(sys.argv[2]).resolve()
        if len(sys.argv) == 3
        else Path("/tmp/ahakey-codex-board-watch-state.json")
    )
    if not board.is_file():
        print(f"board not found: {board}", file=sys.stderr)
        return 2

    offset, last_digest = load_state(state, board)
    descriptor, size = open_board(board)
    if offset > size:
        offset = size

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
    print(
        f"BOARD_EVENT_WATCH_READY board={board} offset={offset}",
        flush=True,
    )

    try:
        while True:
            event = queue.control(None, 1, None)[0]
            if event.fflags & (select.KQ_NOTE_RENAME | select.KQ_NOTE_DELETE):
                os.close(descriptor)
                descriptor, _ = open_board(board)
                register()

            current_size = board.stat().st_size
            if current_size < offset:
                offset = 0

            # Re-read the durable board and parse its actual final entry.
            # Editors may rewrite the file in place (even at the same size), so
            # concatenating only changed bytes can splice an old Kimi entry to
            # a new Cursor entry and produce a false digest/wake.
            text = board.read_text(encoding="utf-8", errors="replace")
            offset = current_size
            message = newest_message(text)
            if should_wake(message):
                digest = hashlib.sha256(message.encode("utf-8")).hexdigest()
                if digest != last_digest:
                    last_digest = emit_wake(message)

            save_state(state, board, offset, last_digest)
    except KeyboardInterrupt:
        return 0
    finally:
        os.close(descriptor)
        queue.close()


if __name__ == "__main__":
    raise SystemExit(main())

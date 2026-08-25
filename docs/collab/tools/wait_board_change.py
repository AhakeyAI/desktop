#!/usr/bin/env python3
"""wait_board_change.py — 回合内等待 board.md 追加事件（Kimi 侧事件加速层）。

用途：Kimi 结束回合前调用，阻塞等待协作板出现新追加内容；一旦有写入立即
输出新增内容并以 0 退出（调用方应继续处理），超时以 1 退出（交回心跳兜底）。

定位：只读、不唤醒模型、不开端口；board.md 仍是唯一事实源。
与 5 分钟 interval 心跳是「加速器 vs 兜底」关系，不是替代。

用法：
  python3 wait_board_change.py [--repo REPO_ROOT] [--timeout SECS]
退出码：0 = 捕获到新增内容；1 = 超时无变化；2 = 参数/文件错误。
"""
from __future__ import annotations

import argparse
import os
import sys
import time


def board_path(repo: str) -> str:
    return os.path.join(repo, "docs", "collab", "board.md")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.getcwd())
    ap.add_argument("--timeout", type=float, default=280.0,
                    help="最长等待秒数（默认 280，须小于调用方工具超时）")
    ap.add_argument("--poll", type=float, default=1.5, help="轮询间隔秒")
    args = ap.parse_args()

    path = board_path(args.repo)
    try:
        st = os.stat(path)
        baseline_size = st.st_size
        baseline_mtime = st.st_mtime_ns
        baseline_ino = st.st_ino
    except OSError as e:
        print(f"无法读取 board.md: {e}", file=sys.stderr)
        return 2

    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        time.sleep(args.poll)
        try:
            st = os.stat(path)
        except OSError:
            continue
        changed = (st.st_mtime_ns != baseline_mtime) or (st.st_ino != baseline_ino)
        if not changed:
            continue
        if st.st_size > baseline_size and st.st_ino == baseline_ino:
            # 正常追加：短防抖后输出新增内容
            time.sleep(0.5)
            with open(path, "rb") as f:
                f.seek(baseline_size)
                chunk = f.read()
            sys.stdout.write(chunk.decode("utf-8", errors="replace"))
        else:
            # 截断/覆盖/替换：不输出正文，明确告警（可能丢历史，需人工核对）
            print(f"\n[WAITER-ALERT] board.md 发生非追加变更 "
                  f"(size {baseline_size} → {st.st_size}, mtime/inode 变化)，"
                  f"请人工检查是否违反 append-only 规则。", file=sys.stdout)
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())

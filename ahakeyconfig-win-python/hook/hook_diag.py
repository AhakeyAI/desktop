"""
Codex / hook 调试：追加写入多份同名日志（见 log_paths）。

环境变量 AHAKEY_HOOK_DEBUG：
- 未设置或为 1：写入日志文件；不向 stderr 打诊断（Codex 对部分 stdout/stderr 很敏感）
- 0：不写文件、不写 stderr（全关）
- 2 / stderr / verbose：写入文件并向 stderr 写诊断（与旧默认行为等价）
"""

from __future__ import annotations

import os
import sys
from datetime import datetime
from pathlib import Path


def _raw_debug_mode() -> str:
    return os.environ.get("AHAKEY_HOOK_DEBUG", "1").strip().lower()


def _file_logging_enabled() -> bool:
    v = _raw_debug_mode()
    return v != "0" and v != "off"


def _stderr_mirror_enabled() -> bool:
    return _raw_debug_mode() in ("2", "stderr", "verbose", "all")


def log_paths() -> list[Path]:
    """
    所有会写入的路径（会去重）：

    1) frozen：与 Hook exe 同目录（常为 .../hook/dist/），便于 Cursor 等工作区读取；
       源码运行：写入 hook_diag.py 所在目录（通常为仓库内 hook/）。
    2) 用户目录 ~/.codex/，与 Codex 配置放一起。
    """

    targets: list[Path] = []
    if getattr(sys, "frozen", False):
        targets.append(Path(sys.executable).resolve().parent / "ahakey-hook-debug.log")
    else:
        targets.append(Path(__file__).resolve().parent / "ahakey-hook-debug.log")

    targets.append(Path.home() / ".codex" / "ahakey-hook-debug.log")

    seen: set[str] = set()
    out: list[Path] = []
    for p in targets:
        key = os.path.normcase(str(p.resolve()))
        if key not in seen:
            seen.add(key)
            out.append(p)
    return out


def log_path() -> Path:
    """兼容旧调用：与工作区最接近的那一份的路径（用于文案展示）。"""
    return log_paths()[0]


def diag_line(source: str, message: str) -> None:
    """source 建议用简短标签，例如 hook_install、codex_UserPromptSubmit。"""

    if not _file_logging_enabled():
        return

    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] [{source}] pid={os.getpid()} {message}\n"

    for p in log_paths():
        try:
            p.parent.mkdir(parents=True, exist_ok=True)
            with open(p, "a", encoding="utf-8") as f:
                f.write(line)
        except OSError:
            pass

    if not _stderr_mirror_enabled():
        return

    try:
        sys.stderr.write("[ahakey-hook] " + line)
        sys.stderr.flush()
    except OSError:
        pass

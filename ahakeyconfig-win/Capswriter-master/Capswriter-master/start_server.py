# coding: utf-8


'''
这个文件仅仅是为了 PyInstaller 打包用
'''

import sys
import os
import traceback
from datetime import datetime
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
FUN_ASR_DIR = BASE_DIR / "util" / "fun_asr_gguf"
if FUN_ASR_DIR.is_dir():
    sys.path.insert(0, str(FUN_ASR_DIR))

from multiprocessing import freeze_support


def _write_startup_crash(exc: BaseException) -> None:
    """Best-effort crash log for very-early import errors (before logger init)."""
    try:
        log_dir = os.environ.get("CAPSWRITER_LOG_DIR") or os.environ.get("VIBE_LOG_DIR")
        if not log_dir:
            log_dir = str(BASE_DIR / "logs")
        Path(log_dir).mkdir(parents=True, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        p = Path(log_dir) / f"server_startup_crash_{ts}.log"
        p.write_text("".join(traceback.format_exception(type(exc), exc, exc.__traceback__)), encoding="utf-8", errors="ignore")
    except Exception:
        pass


try:
    import core_server
except Exception as e:
    _write_startup_crash(e)
    raise

if __name__ == '__main__':
    freeze_support()
    try:
        core_server.init()
        sys.exit(0)
    except Exception as e:
        _write_startup_crash(e)
        raise

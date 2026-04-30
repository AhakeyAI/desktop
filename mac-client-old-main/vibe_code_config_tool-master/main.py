"""
4键键盘配置工具 — 入口
"""

from multiprocessing import freeze_support

from src.core.hook_runtime import maybe_run_embedded_hook_runtime
from src.core.voice_runtime import (
    maybe_run_embedded_voice_runtime,
    prepare_capswriter_environment_from_env,
)


prepare_capswriter_environment_from_env()
freeze_support()

if not maybe_run_embedded_hook_runtime() and not maybe_run_embedded_voice_runtime():
    from src.app import run

    if __name__ == "__main__":
        run()

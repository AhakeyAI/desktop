"""
PyInstaller 入口：捕获所有异常并暂停，避免 exe 闪退看不到报错。
"""
import os
import sys
import traceback

try:
    import hook_install
    hook_install.main()
except Exception:
    traceback.print_exc()
    if getattr(sys, "frozen", False):
        os.system("pause")
    sys.exit(1)

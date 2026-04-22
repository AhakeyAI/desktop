"""
Cursor Hook 安装脚本（委托给 hook/hook_install.py）

推荐直接使用:  python hook/hook_install.py --install-cursor
或打开 UI:     python hook/hook_install.py

本脚本仅为兼容旧用法，将调用 hook 目录下的统一入口完成 Cursor 的安装/卸载。

用法:
    python install_cursor_hook.py           # 安装 Cursor hooks
    python install_cursor_hook.py --uninstall   # 卸载 Cursor hooks
"""

import subprocess
import sys
from pathlib import Path


def main():
    repo_root = Path(__file__).resolve().parent
    hook_install = repo_root / "hook" / "hook_install.py"
    if not hook_install.is_file():
        print("[ERROR] 未找到 hook/hook_install.py，请确保在仓库根目录运行。")
        sys.exit(1)

    args = sys.argv[1:]
    if "--uninstall" in args or "-u" in args:
        subprocess.run([sys.executable, str(hook_install), "--uninstall-cursor"], check=False)
    elif "--help" in args or "-h" in args:
        print(__doc__)
        subprocess.run([sys.executable, str(hook_install), "--help"])
    else:
        subprocess.run([sys.executable, str(hook_install), "--install-cursor"], check=False)


if __name__ == "__main__":
    main()

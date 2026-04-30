"""
Claude / Cursor Hook 安装 & 分发工具（单入口）

- 无参数运行: 打开 Tkinter UI，可安装/卸载 Claude 或 Cursor 的 hooks
- 传入事件名运行: 分发到对应 hook 模块执行（支持 Claude 的 PascalCase 与 Cursor 的小驼峰）

用法:
    python hook_install.py                      # 打开 UI 界面
    python hook_install.py --install-cursor     # 仅安装 Cursor hooks
    python hook_install.py --uninstall-cursor   # 仅卸载 Cursor hooks
    python hook_install.py SessionStart        # Claude 事件名 -> SessionStart.run()
    python hook_install.py sessionStart         # Cursor 事件名 -> SessionStart.run()
"""

import json
import os
import platform
import shutil
import subprocess
import sys
import traceback
from datetime import datetime
from pathlib import Path

# ============================================================
# 显式 import 所有 hook 模块，确保 PyInstaller 能收集依赖
# ============================================================
import SessionStart
import SessionEnd
import PreToolUse
import PostToolUse
import PermissionRequest
import Notification
import TaskCompleted
import Stop
import UserPromptSubmit

# 事件名 -> 模块映射（用于分发，Claude 使用 PascalCase）
DISPATCH = {
    "SessionStart": SessionStart,
    "SessionEnd": SessionEnd,
    "PreToolUse": PreToolUse,
    "PostToolUse": PostToolUse,
    "PermissionRequest": PermissionRequest,
    "Notification": Notification,
    "TaskCompleted": TaskCompleted,
    "Stop": Stop,
    "UserPromptSubmit": UserPromptSubmit,
}

# Cursor 事件名（小驼峰）-> 模块映射，与 DISPATCH 共用同一批模块
CURSOR_DISPATCH = {
    "sessionStart": SessionStart,
    "sessionEnd": SessionEnd,
    "preToolUse": PreToolUse,
    "postToolUse": PostToolUse,
    "stop": Stop,
}

# Hook 事件定义: (事件名, 超时时间)
HOOK_EVENTS = [
    ("SessionStart", 10),
    ("SessionEnd", 10),
    ("PreToolUse", 10),
    ("PostToolUse", 10),
    ("PermissionRequest", 60),
    ("Notification", 10),
    ("TaskCompleted", 10),
    ("Stop", 10),
    ("UserPromptSubmit", 10),
]


# ============================================================
# Hook 分发逻辑
# ============================================================
def dispatch_hook(event_name):
    """根据事件名分发到对应的 hook 模块执行。"""
    module = DISPATCH.get(event_name)
    if module is None:
        print(f"Unknown event: {event_name}")
        sys.exit(1)
    module.run()


# ============================================================
# 安装/卸载逻辑
# ============================================================
def is_frozen():
    """判断当前是否为 PyInstaller 打包的可执行程序。"""
    return getattr(sys, 'frozen', False)


def get_self_path() -> str:
    """获取当前程序自身的路径（exe 或 py 脚本）。"""
    if is_frozen():
        return sys.executable
    else:
        return os.path.abspath(__file__)


def get_claude_global_settings_path() -> Path:
    """获取 Claude Code 全局配置文件路径（跨平台）。"""
    return Path.home() / ".claude" / "settings.json"


def detect_python_executable() -> str:
    """检测当前系统可用的 python 可执行文件名。"""
    current = sys.executable
    if current:
        try:
            subprocess.run(
                [current, "--version"],
                capture_output=True, timeout=5, check=True
            )
            return current
        except Exception:
            pass

    candidates = ["python3", "python", "py"]
    if platform.system() == "Windows":
        candidates = ["python", "py", "python3"]

    for name in candidates:
        try:
            result = subprocess.run(
                [name, "--version"],
                capture_output=True, timeout=5, check=True
            )
            if result.returncode == 0:
                return name
        except Exception:
            continue

    return ""


def build_hook_command(event_name: str) -> str:
    """
    构建单个 hook 的调用命令。
    - 可执行程序: "E:/path/hook_install.exe SessionStart"
    - Python 脚本: "C:/Python39/python.exe" "E:/path/hook_install.py SessionStart"
    """
    self_path = get_self_path().replace("\\", "/")

    if is_frozen():
        return f'"{self_path}" {event_name}'
    else:
        python_exe = detect_python_executable().replace("\\", "/")
        return f'"{python_exe}" "{self_path}" {event_name}'


def build_hooks_config() -> dict:
    """构建完整的 hooks 配置字典。"""
    hooks = {}
    for event_name, timeout in HOOK_EVENTS:
        command = build_hook_command(event_name)
        hooks[event_name] = [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": command,
                        "timeout": timeout,
                    }
                ]
            }
        ]
    return hooks


def backup_settings(settings_path: Path):
    """备份现有配置文件。"""
    if not settings_path.is_file():
        return None
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = settings_path.with_name(f"settings.json.bak.{timestamp}")
    shutil.copy2(settings_path, backup_path)
    return backup_path


def load_settings(settings_path: Path) -> dict:
    """加载现有配置。"""
    if not settings_path.is_file():
        return {}
    try:
        with open(settings_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {}


def save_settings(settings_path: Path, settings: dict):
    """保存配置文件。"""
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    with open(settings_path, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)


def install_hooks() -> str:
    """安装 hooks，返回结果信息。"""
    settings_path = get_claude_global_settings_path()

    # 备份
    backup = backup_settings(settings_path)
    backup_msg = f"已备份: {backup.name}" if backup else "无需备份(新配置)"

    # 加载、合并、保存
    settings = load_settings(settings_path)
    new_hooks = build_hooks_config()
    settings["hooks"] = new_hooks
    save_settings(settings_path, settings)

    mode = "可执行程序" if is_frozen() else "Python 脚本"
    lines = [
        f"安装成功! ({mode}模式)",
        f"{backup_msg}",
        f"已注册 {len(new_hooks)} 个 hook 事件",
        f"配置文件: {settings_path}",
        "",
        "示例命令:",
        f"  {build_hook_command('SessionStart')}",
    ]
    return "\n".join(lines)


def uninstall_hooks() -> str:
    """卸载 hooks，返回结果信息。"""
    settings_path = get_claude_global_settings_path()

    if not settings_path.is_file():
        return "配置文件不存在，无需卸载。"

    settings = load_settings(settings_path)
    if "hooks" in settings:
        del settings["hooks"]
        save_settings(settings_path, settings)
        return "卸载成功!\n已从配置中移除 hooks。"
    else:
        return "配置中不存在 hooks，无需卸载。"


# ============================================================
# Cursor 安装/卸载
# ============================================================
def get_cursor_hooks_path() -> Path:
    """获取 Cursor 用户级 hooks 配置文件路径。"""
    return Path.home() / ".cursor" / "hooks.json"


# Cursor 事件列表: (cursor_event_name, timeout)
CURSOR_HOOK_EVENTS = [
    ("sessionStart", 10),
    ("sessionEnd", 10),
    ("preToolUse", 10),
    ("postToolUse", 10),
    ("stop", 10),
]


def build_cursor_hook_command(cursor_event_name: str) -> str:
    """
    构建 Cursor 单条 hook 的 command（无外层引号，避免 Windows PowerShell 解析错误）。
    格式: python_exe self_path cursor_event_name
    """
    self_path = get_self_path().replace("\\", "/")
    if is_frozen():
        return f"{self_path} {cursor_event_name}"
    python_exe = detect_python_executable().replace("\\", "/")
    return f"{python_exe} {self_path} {cursor_event_name}"


def build_cursor_hooks_config() -> dict:
    """构建 Cursor hooks.json 的 hooks 部分。"""
    hooks = {}
    for cursor_event, timeout in CURSOR_HOOK_EVENTS:
        hooks[cursor_event] = [
            {
                "command": build_cursor_hook_command(cursor_event),
                "timeout": timeout,
            }
        ]
    return hooks


def install_cursor_hooks() -> str:
    """安装 hooks 到 Cursor，返回结果信息。"""
    settings_path = get_cursor_hooks_path()
    if settings_path.is_file():
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_path = settings_path.with_name(f"hooks.json.bak.{timestamp}")
        shutil.copy2(settings_path, backup_path)

    settings = load_settings(settings_path)
    new_hooks = build_cursor_hooks_config()
    existing_hooks = settings.get("hooks", {})
    for name, defs in new_hooks.items():
        existing_hooks[name] = defs
    settings["hooks"] = existing_hooks
    settings["version"] = 1
    save_settings(settings_path, settings)

    mode = "可执行程序" if is_frozen() else "Python 脚本"
    lines = [
        "Cursor 安装成功! ({0}模式)".format(mode),
        "已注册 {0} 个 hook 事件到 {1}".format(len(new_hooks), settings_path),
        "",
        "示例命令:",
        "  " + build_cursor_hook_command("sessionStart"),
    ]
    return "\n".join(lines)


def uninstall_cursor_hooks() -> str:
    """从 Cursor 配置中移除 hooks。"""
    settings_path = get_cursor_hooks_path()
    if not settings_path.is_file():
        return "Cursor 配置文件不存在，无需卸载。"

    settings = load_settings(settings_path)
    if "hooks" in settings:
        del settings["hooks"]
        save_settings(settings_path, settings)
        return "Cursor 卸载成功!\n已从配置中移除 hooks。"
    return "配置中不存在 hooks，无需卸载。"


# ============================================================
# Tkinter UI 界面
# ============================================================
def show_ui():
    """显示 Tkinter 安装/卸载界面。"""
    import tkinter as tk
    from tkinter import scrolledtext

    root = tk.Tk()
    root.title("Claude / Cursor Hook 管理工具")
    root.geometry("520x480")
    root.resizable(False, False)

    # --- 状态信息 ---
    info_frame = tk.LabelFrame(root, text="当前状态", padx=10, pady=5)
    info_frame.pack(fill=tk.X, padx=10, pady=(10, 5))

    mode_text = "可执行程序 (exe)" if is_frozen() else "Python 脚本"
    tk.Label(info_frame, text=f"运行模式:  {mode_text}", anchor="w").pack(fill=tk.X)

    self_path = get_self_path().replace("\\", "/")
    tk.Label(info_frame, text=f"程序路径:  {self_path}", anchor="w", wraplength=480).pack(fill=tk.X)

    claude_status_var = tk.StringVar()
    cursor_status_var = tk.StringVar()

    def refresh_status():
        sp = get_claude_global_settings_path()
        if sp.is_file():
            s = load_settings(sp)
            has = "hooks" in s and len(s["hooks"]) > 0
        else:
            has = False
        claude_status_var.set("Claude Hook 状态: " + ("已安装" if has else "未安装"))

        cp = get_cursor_hooks_path()
        if cp.is_file():
            cs = load_settings(cp)
            c_has = "hooks" in cs and len(cs.get("hooks", {})) > 0
        else:
            c_has = False
        cursor_status_var.set("Cursor Hook 状态: " + ("已安装" if c_has else "未安装"))

    refresh_status()
    tk.Label(info_frame, textvariable=claude_status_var, anchor="w").pack(fill=tk.X)
    tk.Label(info_frame, textvariable=cursor_status_var, anchor="w").pack(fill=tk.X)

    # --- 按钮: Claude ---
    btn_frame = tk.Frame(root)
    btn_frame.pack(fill=tk.X, padx=10, pady=5)
    tk.Label(btn_frame, text="Claude:", anchor="w").pack(side=tk.LEFT, padx=(0, 8))

    # --- 按钮: Cursor ---
    btn_frame_cursor = tk.Frame(root)
    btn_frame_cursor.pack(fill=tk.X, padx=10, pady=(0, 5))
    tk.Label(btn_frame_cursor, text="Cursor:", anchor="w").pack(side=tk.LEFT, padx=(0, 8))

    # --- 输出区域 ---
    output_frame = tk.LabelFrame(root, text="输出", padx=5, pady=5)
    output_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=(0, 10))

    output_text = scrolledtext.ScrolledText(output_frame, height=10, state=tk.DISABLED)
    output_text.pack(fill=tk.BOTH, expand=True)

    def append_output(msg):
        output_text.config(state=tk.NORMAL)
        output_text.insert(tk.END, msg + "\n")
        output_text.see(tk.END)
        output_text.config(state=tk.DISABLED)

    # --- 底部操作区：安装向导式横线 + 右下角按钮 ---
    footer_strip = tk.Frame(root)
    footer_strip.pack(fill=tk.X, side=tk.BOTTOM)
    footer_frame = tk.Frame(footer_strip, bg=root.cget("bg"))
    footer_frame.pack(fill=tk.X, padx=10, pady=(8, 10))

    def on_next_step():
        root.destroy()

    def on_cancel():
        root.destroy()

    # 与经典安装向导接近：Segoe UI 9pt、灰底凸起、默认按钮用蓝色外框 Frame 模拟双层边
    _win = platform.system() == "Windows"
    _btn_font = ("Segoe UI", 9) if _win else ("TkDefaultFont", 9)
    _btn_face = "#F0F0F0"
    _btn_active = "#E6E6E6"
    _default_ring = "#0078D7"

    next_outer = tk.Frame(footer_frame, bg=_default_ring, padx=2, pady=2)
    next_inner = tk.Button(
        next_outer,
        text="下一步(N)",
        command=on_next_step,
        font=_btn_font,
        width=10,
        bg=_btn_face,
        fg="black",
        activebackground=_btn_active,
        activeforeground="black",
        relief=tk.RAISED,
        borderwidth=1,
        padx=4,
        pady=3,
        highlightthickness=0,
        takefocus=True,
    )
    next_inner.pack(fill=tk.BOTH, expand=True)

    cancel_btn = tk.Button(
        footer_frame,
        text="取消",
        command=on_cancel,
        font=_btn_font,
        width=10,
        bg=_btn_face,
        fg="black",
        activebackground=_btn_active,
        activeforeground="black",
        relief=tk.RAISED,
        borderwidth=1,
        padx=4,
        pady=3,
        highlightthickness=0,
        takefocus=True,
    )

    cancel_btn.pack(side=tk.RIGHT)
    next_outer.pack(side=tk.RIGHT, padx=(0, 8))

    root.after_idle(next_inner.focus_set)

    # 键盘快捷键：N -> 下一步，Esc -> 取消
    root.bind("<KeyPress-n>", lambda e: on_next_step())
    root.bind("<KeyPress-N>", lambda e: on_next_step())
    root.bind("<Escape>", lambda e: on_cancel())

    # --- Claude 按钮回调 ---
    def on_install():
        try:
            result = install_hooks()
            append_output(result)
        except Exception as e:
            append_output(f"安装失败: {e}")
        refresh_status()

    def on_uninstall():
        try:
            result = uninstall_hooks()
            append_output(result)
        except Exception as e:
            append_output(f"卸载失败: {e}")
        refresh_status()

    tk.Button(btn_frame, text="安装 Hooks", command=on_install,
              width=14, height=2, bg="#4CAF50", fg="white").pack(side=tk.LEFT, padx=(0, 10))
    tk.Button(btn_frame, text="卸载 Hooks", command=on_uninstall,
              width=14, height=2, bg="#f44336", fg="white").pack(side=tk.LEFT)

    # --- Cursor 按钮回调 ---
    def on_install_cursor():
        try:
            result = install_cursor_hooks()
            append_output(result)
        except Exception as e:
            append_output("Cursor 安装失败: {0}".format(e))
        refresh_status()

    def on_uninstall_cursor():
        try:
            result = uninstall_cursor_hooks()
            append_output(result)
        except Exception as e:
            append_output("Cursor 卸载失败: {0}".format(e))
        refresh_status()

    tk.Button(btn_frame_cursor, text="安装 Hooks", command=on_install_cursor,
              width=14, height=2, bg="#2196F3", fg="white").pack(side=tk.LEFT, padx=(0, 10))
    tk.Button(btn_frame_cursor, text="卸载 Hooks", command=on_uninstall_cursor,
              width=14, height=2, bg="#FF9800", fg="white").pack(side=tk.LEFT)

    root.mainloop()


# ============================================================
# 入口
# ============================================================
def main():
    args = sys.argv[1:]

    if not args:
        # 无参数 -> 打开 UI 界面
        show_ui()
    elif args[0] == "--install-cursor":
        print(install_cursor_hooks())
    elif args[0] == "--uninstall-cursor":
        print(uninstall_cursor_hooks())
    elif args[0] in DISPATCH:
        # Claude 事件名（PascalCase）-> 分发执行
        dispatch_hook(args[0])
    elif args[0] in CURSOR_DISPATCH:
        # Cursor 事件名（小驼峰）-> 分发执行
        CURSOR_DISPATCH[args[0]].run()
    elif args[0] == "--help" or args[0] == "-h":
        print(__doc__)
    else:
        sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        traceback.print_exc()
        if getattr(sys, "frozen", False):
            input("\n按回车键退出...")
        raise
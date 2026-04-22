"""
Claude Code Hook 安装脚本
将 hook 文件夹中的钩子脚本注册到 Claude Code 全局配置中。

用法:
    python install_hook.py                  # 自动检测 hook 文件夹（脚本同级目录的 ../hook）
    python install_hook.py /path/to/hook    # 手动指定 hook 文件夹路径
    python install_hook.py --uninstall      # 从全局配置中移除 hooks（从备份恢复）
"""

import json
import os
import platform
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

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


def get_claude_global_settings_path() -> Path:
    """获取 Claude Code 全局配置文件路径（跨平台）"""
    home = Path.home()
    return home / ".claude" / "settings.json"


def detect_python_executable() -> str:
    """
    检测当前系统可用的 python 可执行文件名。
    按优先级尝试: python3, python, py
    """
    # 优先用当前运行本脚本的解释器
    current = sys.executable
    if current:
        # 验证它确实能工作
        try:
            subprocess.run(
                [current, "--version"],
                capture_output=True, timeout=5, check=True
            )
            return current
        except Exception:
            pass

    # 候选列表
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

    print("[ERROR] 未找到可用的 Python 解释器，请确认 python 已加入 PATH。")
    sys.exit(1)


def resolve_hook_dir(arg) -> Path:
    """
    解析 hook 文件夹路径。
    - 如果用户传入了路径参数，则使用该路径。
    - 否则自动推断为本脚本所在目录的同级 hook 文件夹。
    """
    if arg:
        hook_dir = Path(arg).resolve()
    else:
        # 默认: 脚本所在目录一级下的 hook 文件夹
        script_dir = Path(__file__).resolve().parent
        hook_dir = script_dir / "hook"

    if not hook_dir.is_dir():
        print(f"[ERROR] Hook 文件夹不存在: {hook_dir}")
        sys.exit(1)

    # 验证所需的 hook 脚本是否存在
    missing = []
    for event_name, _ in HOOK_EVENTS:
        script_path = hook_dir / f"{event_name}.py"
        if not script_path.is_file():
            missing.append(f"{event_name}.py")

    if missing:
        print(f"[WARN] hook 文件夹中缺少以下脚本（将跳过）: {', '.join(missing)}")

    return hook_dir


def build_hooks_config(python_exe: str, hook_dir: Path) -> dict:
    """根据 hook 文件夹中实际存在的脚本构建 hooks 配置。"""
    hooks = {}
    # 使用正斜杠路径，兼容性更好
    hook_dir_str = str(hook_dir).replace("\\", "/")

    for event_name, timeout in HOOK_EVENTS:
        script_path = hook_dir / f"{event_name}.py"
        if not script_path.is_file():
            continue

        script_path_str = f"{hook_dir_str}/{event_name}.py"
        # 如果 python_exe 包含路径，也统一用正斜杠
        python_exe_normalized = python_exe.replace("\\", "/")

        hooks[event_name] = [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": f'"{python_exe_normalized}" "{script_path_str}"',
                        "timeout": timeout,
                    }
                ]
            }
        ]

    return hooks


def backup_settings(settings_path: Path):
    """备份现有配置文件，返回备份路径。"""
    if not settings_path.is_file():
        return None

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = settings_path.with_name(f"settings.json.bak.{timestamp}")
    shutil.copy2(settings_path, backup_path)
    print(f"[INFO] 已备份原始配置: {backup_path}")
    return backup_path


def load_settings(settings_path: Path) -> dict:
    """加载现有配置，文件不存在则返回空 dict。"""
    if not settings_path.is_file():
        return {}
    try:
        with open(settings_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"[WARN] 读取配置文件失败 ({e})，将创建新配置。")
        return {}


def save_settings(settings_path: Path, settings: dict):
    """保存配置文件。"""
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    with open(settings_path, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
    print(f"[INFO] 配置已写入: {settings_path}")


def install(hook_dir_arg = None):
    """安装 hooks 到全局配置。"""
    settings_path = get_claude_global_settings_path()
    print(f"[INFO] 全局配置路径: {settings_path}")

    # 1. 解析 hook 文件夹
    hook_dir = resolve_hook_dir(hook_dir_arg)
    print(f"[INFO] Hook 文件夹: {hook_dir}")

    # 2. 检测 python 可执行文件
    python_exe = detect_python_executable()
    print(f"[INFO] Python 解释器: {python_exe}")

    # 3. 备份
    backup_settings(settings_path)

    # 4. 加载现有配置并合并
    settings = load_settings(settings_path)
    new_hooks = build_hooks_config(python_exe, hook_dir)

    settings["hooks"] = new_hooks

    # 5. 写入
    save_settings(settings_path, settings)

    print(f"\n[OK] 已成功安装 {len(new_hooks)} 个 hook 事件:")
    for name in new_hooks:
        print(f"  - {name}")


def uninstall():
    """从全局配置中移除 hooks，尝试从最近的备份恢复。"""
    settings_path = get_claude_global_settings_path()

    if not settings_path.is_file():
        print("[INFO] 全局配置文件不存在，无需卸载。")
        return

    # 查找最新的备份文件
    backup_files = sorted(
        settings_path.parent.glob("settings.json.bak.*"),
        reverse=True,
    )

    if backup_files:
        latest_backup = backup_files[0]
        shutil.copy2(latest_backup, settings_path)
        print(f"[OK] 已从备份恢复配置: {latest_backup}")
    else:
        # 没有备份，仅移除 hooks 键
        settings = load_settings(settings_path)
        if "hooks" in settings:
            del settings["hooks"]
            save_settings(settings_path, settings)
            print("[OK] 已从配置中移除 hooks。")
        else:
            print("[INFO] 配置中不存在 hooks，无需卸载。")


def main():
    args = sys.argv[1:]

    if "--uninstall" in args:
        uninstall()
    elif "--help" in args or "-h" in args:
        print(__doc__)
    else:
        hook_dir_arg = args[0] if args else None
        install(hook_dir_arg)


if __name__ == "__main__":
    main()

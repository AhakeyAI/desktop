"""云端 API 与登录信息的本地存储（QSettings）。"""

import sys
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from PySide6.QtCore import QSettings

_ORG = "VibeKeyboard"
_APP = "VibeCodeConfigTool"

# 发布时在源码中填入正式云托管根地址（不含末尾斜杠，须含 https://）。界面不向用户展示 API 地址。
# 注意：若用户曾运行过本工具，QSettings 里已写入 cloud/api_base，会一直优先于本常量——
# 仅改此处不会生效，需清除已存地址（见 clear_stored_api_base）或手动删注册表该项。
DEFAULT_API_BASE = "https://typeless-220629-6-1398334410.sh.run.tcloudbase.com"
LEGACY_API_BASES = {
    "https://vibe-220629-6-1398334410.sh.run.tcloudbase.com",
}


def _normalize_api_base(url: str) -> str:
    u = (url or "").strip().rstrip("/")
    if not u:
        return ""
    if "://" not in u:
        u = "https://{}".format(u)
    return u


def _s() -> "QSettings":
    # 延迟导入：便于在无 Qt DLL 环境下仅调用 clear_stored_api_base()
    from PySide6.QtCore import QSettings

    return QSettings(_ORG, _APP)


def get_api_base() -> str:
    return _s().value("cloud/api_base", "", str)


def effective_api_base() -> str:
    """供客户端请求使用：已保存地址优先，否则为 DEFAULT_API_BASE。"""
    u = _normalize_api_base(get_api_base())
    if u in LEGACY_API_BASES:
        return _normalize_api_base(DEFAULT_API_BASE)
    if u:
        return u
    return _normalize_api_base(DEFAULT_API_BASE)


def set_api_base(url: str) -> None:
    _s().setValue("cloud/api_base", url)


def _clear_stored_api_base_windows() -> None:
    """与 QSettings(NativeFormat) 在注册表中的布局一致：cloud/api_base 多为多级子键。"""
    import winreg

    root = winreg.HKEY_CURRENT_USER
    # 常见：...\\VibeCodeConfigTool\\cloud\\api_base 为子键，(默认) 为 URL
    leaf = r"Software\VibeKeyboard\VibeCodeConfigTool\cloud\api_base"
    try:
        winreg.DeleteKey(root, leaf)
        return
    except OSError:
        pass
    # 备选：...\\cloud 下名为 api_base 的 REG_SZ
    try:
        parent = winreg.OpenKey(root, r"Software\VibeKeyboard\VibeCodeConfigTool\cloud", 0, winreg.KEY_SET_VALUE)
    except OSError:
        return
    try:
        winreg.DeleteValue(parent, "api_base")
    except OSError:
        pass
    finally:
        winreg.CloseKey(parent)


def clear_stored_api_base() -> None:
    """删除本地保存的 API 根地址，使 effective_api_base() 回退到 DEFAULT_API_BASE。

    Windows 下用注册表实现，不依赖 PySide6/Qt DLL，便于命令行一键清理。
    """
    if sys.platform == "win32":
        _clear_stored_api_base_windows()
        return
    _s().remove("cloud/api_base")


def get_token() -> str:
    return _s().value("cloud/access_token", "", str)


def set_token(token: str) -> None:
    _s().setValue("cloud/access_token", token)


def clear_token() -> None:
    _s().remove("cloud/access_token")


def get_remember() -> bool:
    return _s().value("cloud/remember", False, bool)


def set_remember(v: bool) -> None:
    _s().setValue("cloud/remember", v)


def get_saved_phone() -> str:
    return _s().value("cloud/saved_phone", "", str)


def set_saved_phone(phone: str) -> None:
    _s().setValue("cloud/saved_phone", phone)


def get_saved_password() -> str:
    return _s().value("cloud/saved_password", "", str)


def set_saved_password(pw: str) -> None:
    _s().setValue("cloud/saved_password", pw)

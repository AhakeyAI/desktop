"""Typeless 本地配置文件读写，供 CapsWriter 客户端读取。"""

import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, MutableMapping

# 不再持久化到 typeless_config.json 的顶层键（历史或冗余字段）
_STRIP_TOP_KEYS = ("api_base", "token_balance", "typeless_balance")


def _sanitize_typeless_dict(d: MutableMapping[str, Any]) -> None:
    for k in _STRIP_TOP_KEYS:
        d.pop(k, None)
    u = d.get("user")
    if isinstance(u, dict):
        u.pop("is_admin", None)


def typeless_config_path() -> Path:
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
    elif sys.platform == "darwin":
        base = str(Path.home() / "Library" / "Application Support")
    else:
        base = str(Path.home() / ".local" / "share")
    d = Path(base) / "VibeKeyboard"
    d.mkdir(parents=True, exist_ok=True)
    return d / "typeless_config.json"


def default_payload() -> Dict[str, Any]:
    return {
        "schema_version": 1,
        # api_base 不再写入本文件（避免在共享目录明文暴露云端根地址；CapsWriter 见 text_optimizer 解析逻辑）
        "access_token": "",
        "typeless_enabled": False,
        "token_valid_until": None,
        # 配额快照（用于 UI 在每次语义处理后“自动刷新 used/limit 展示”）
        "limit_daily": 0,
        "limit_weekly": 0,
        "limit_monthly": 0,
        "used_daily": 0,
        "used_weekly": 0,
        "used_monthly": 0,
        "user": None,
    }


def ensure_typeless_file() -> Path:
    path = typeless_config_path()
    if not path.exists():
        path.write_text(
            json.dumps(default_payload(), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    return path


def load() -> Dict[str, Any]:
    path = typeless_config_path()
    if not path.exists():
        return default_payload()
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            return default_payload()
        out = default_payload()
        out.update(data)
        _sanitize_typeless_dict(out)
        return out
    except Exception:
        return default_payload()


def save(data: Dict[str, Any]) -> None:
    path = typeless_config_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    merged = default_payload()
    merged.update(data)
    _sanitize_typeless_dict(merged)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(merged, f, ensure_ascii=False, indent=2)


def set_typeless_enabled(enabled: bool) -> None:
    data = load()
    data["typeless_enabled"] = bool(enabled)
    save(data)


def get_typeless_enabled() -> bool:
    return bool(load().get("typeless_enabled"))


def patch_cloud_token(access_token: str) -> None:
    """同步登录令牌（不向 typeless_config.json 写入 api_base）。"""
    data = load()
    data["access_token"] = access_token or ""
    save(data)


def set_user_profile(me: Dict[str, Any]) -> None:
    """同步 /users/me 到本地 typeless_config.json。"""
    data = load()
    data["user"] = {
        "phone": me.get("phone"),
        "user_id": me.get("id") or me.get("user_id"),
    }
    data["token_valid_until"] = me.get("token_valid_until")
    # 把 used/limit 也写入本地，后续 Capswriter 每次使用后可更新这些字段，
    # UI 便能在不频繁请求云端 /users/me 的情况下自动刷新展示。
    data["limit_daily"] = int(me.get("limit_daily") or 0)
    data["limit_weekly"] = int(me.get("limit_weekly") or 0)
    data["limit_monthly"] = int(me.get("limit_monthly") or 0)
    data["used_daily"] = int(me.get("used_daily") or 0)
    data["used_weekly"] = int(me.get("used_weekly") or 0)
    data["used_monthly"] = int(me.get("used_monthly") or 0)
    save(data)


def clear_session_keep_toggle() -> None:
    data = load()
    data["access_token"] = ""
    data["user"] = None
    data["token_valid_until"] = None
    data["limit_daily"] = 0
    data["limit_weekly"] = 0
    data["limit_monthly"] = 0
    data["used_daily"] = 0
    data["used_weekly"] = 0
    data["used_monthly"] = 0
    save(data)

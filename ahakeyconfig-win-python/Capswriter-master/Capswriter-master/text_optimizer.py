# coding: utf-8
"""
文本优化（Typeless）：
1) 读取本地 typeless_config.json
2) 在 typeless_enabled + access_token 可用时请求云端 /api/v1/typeless/process
3) API 根地址由环境变量或内置默认给出（不再从 JSON 读 api_base）；与 vibe_code_config_tool typeless_store 一致
4) 写回 JSON 时剥离 token_balance、typeless_balance、user.is_admin 等字段
5) 若本地 token_valid_until 已过期，则直接跳过云端调用
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, MutableMapping, Optional

try:
    from util.logger import get_logger

    _logger = get_logger("client")
except Exception:
    _logger = logging.getLogger("text_optimizer")

# 与 vibe_code_config_tool.src.core.cloud_settings.DEFAULT_API_BASE 保持一致；可用环境变量覆盖
_FALLBACK_TYPELESS_API_BASE = (
    "https://typeless-220629-6-1398334410.sh.run.tcloudbase.com"
)


def _normalize_api_base(url: str) -> str:
    u = (url or "").strip().rstrip("/")
    if not u:
        return ""
    if "://" not in u:
        u = "https://{}".format(u)
    return u


def _resolve_typeless_api_base(legacy_from_json: str = "") -> str:
    """优先环境变量，其次内置默认，最后兼容尚未迁移的 typeless_config.json 中的 api_base（读入后会被 sanitize 掉不落盘）。"""
    for key in ("VIBE_TYPELESS_API_BASE", "VIBE_API_BASE"):
        v = _normalize_api_base(os.environ.get(key) or "")
        if v:
            return v
    v = _normalize_api_base(_FALLBACK_TYPELESS_API_BASE)
    if v:
        return v
    return _normalize_api_base(legacy_from_json)


def _sanitize_typeless_config_dict(d: MutableMapping[str, Any]) -> None:
    """与键盘配置工具 typeless_store 一致：不写回 api_base、余额类字段；user 不含 is_admin。"""
    for k in ("api_base", "token_balance", "typeless_balance"):
        d.pop(k, None)
    u = d.get("user")
    if isinstance(u, dict):
        u.pop("is_admin", None)


def _typeless_config_path() -> Path:
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
    elif sys.platform == "darwin":
        base = str(Path.home() / "Library" / "Application Support")
    else:
        base = str(Path.home() / ".local" / "share")
    return Path(base) / "VibeKeyboard" / "typeless_config.json"


def _load_typeless_config() -> Dict[str, Any]:
    path = _typeless_config_path()
    if not path.is_file():
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _save_typeless_config(data: Dict[str, Any]) -> None:
    path = _typeless_config_path()
    try:
        if isinstance(data, dict):
            _sanitize_typeless_config_dict(data)
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception:
        # 写入失败不影响识别/排版结果
        pass


def _parse_valid_until(raw: Any) -> Optional[datetime]:
    if not isinstance(raw, str):
        return None
    s = raw.strip()
    if not s:
        return None
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            pass
    try:
        # 兼容 "2026-03-24T08:00:00+08:00" 这类格式
        return datetime.fromisoformat(s).replace(tzinfo=None)
    except Exception:
        return None


def apply_if_enabled(text: str) -> str:
    """
    条件满足时调用云端 Typeless；否则返回原文。
    """
    cfg_path = _typeless_config_path()

    if not (text or "").strip():
        _logger.debug("Typeless 跳过：空文本")
        return text

    cfg = _load_typeless_config()
    legacy_api = ""
    if isinstance(cfg, dict):
        legacy_api = (cfg.get("api_base") or "").strip()
        _sanitize_typeless_config_dict(cfg)
    if not cfg.get("typeless_enabled"):
        _logger.debug(
            "Typeless 跳过：typeless_enabled=%r 配置=%s",
            cfg.get("typeless_enabled"),
            cfg_path,
        )
        return text

    valid_until = _parse_valid_until(cfg.get("token_valid_until"))
    if (valid_until is None) or (datetime.utcnow() > valid_until):
        _logger.info(
            "Typeless token_valid_until=%s",
            cfg.get("token_valid_until"),
        )
        return text

    api_base = _resolve_typeless_api_base(legacy_api)
    token = (cfg.get("access_token") or "").strip()
    if not api_base:
        _logger.info(
            "Typeless 跳过：无可用 API 根，请设置环境变量 VIBE_TYPELESS_API_BASE 或更新 CapsWriter 中 _FALLBACK_TYPELESS_API_BASE；配置=%s",
            cfg_path,
        )
        return text
    if not token:
        _logger.info("Typeless 跳过：缺少 access_token 配置=%s", cfg_path)
        return text

    url = f"{api_base}/api/v1/typeless/process"
    _logger.info("Typeless 请求：POST %s", url)

    payload = json.dumps({"text": text}, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        method="POST",
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Authorization": f"Bearer {token}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            http_status = getattr(resp, "status", None) or resp.getcode()
            _logger.info("Typeless 响应：HTTP %s，长度=%s", http_status, len(raw))
    except urllib.error.HTTPError as e:
        body_head = ""
        try:
            body_head = (e.read() or b"")[:300].decode("utf-8", errors="replace")
        except Exception:
            pass
        _logger.info(
            "Typeless HTTP错误：url=%s status=%s body_head=%s",
            url,
            e.code,
            body_head,
        )
        return text
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        _logger.info("Typeless 网络错误：url=%s err=%s", url, e)
        return text

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        _logger.info("Typeless 返回非JSON：%r", raw[:200])
        return text

    if not isinstance(data, dict):
        _logger.info("Typeless 返回结构不是对象")
        return text

    biz_code = data.get("code")
    if biz_code != 0:
        _logger.info(
            "Typeless 业务错误：code=%s errorMsg=%r",
            biz_code,
            data.get("errorMsg"),
        )
        return text

    inner = data.get("data") if isinstance(data.get("data"), dict) else {}
    quota = inner.get("quota") if isinstance(inner.get("quota"), dict) else None

    out = inner.get("text") if isinstance(inner.get("text"), str) else None
    if out is None and isinstance(inner.get("result"), str):
        out = inner.get("result")

    # 写回本地配额快照：用于 UI 在“每次使用后”自动刷新 displayed used/limit。
    if isinstance(quota, dict):
        if "token_valid_until" in quota:
            cfg["token_valid_until"] = quota.get("token_valid_until")
        for key in (
            "limit_daily",
            "limit_weekly",
            "limit_monthly",
            "used_daily",
            "used_weekly",
            "used_monthly",
        ):
            if key in quota:
                try:
                    cfg[key] = int(quota.get(key) or 0)
                except Exception:
                    pass
        cfg["quota_updated_at"] = time.time()
        _save_typeless_config(cfg)
    if isinstance(out, str) and out.strip():
        result = out.strip()
        _logger.info("Typeless 成功：in_len=%s out_len=%s", len(text), len(result))
        try:
            with open("debug_ai.txt", "a", encoding="utf-8") as f:
                f.write(
                    "[{}] typeless | in={} -> out={}\n".format(
                        time.strftime("%H:%M:%S"), text[:200], result[:200]
                    )
                )
        except OSError:
            pass
        return result

    _logger.info("Typeless code=0 但 data.text/result 为空")
    return text


async def optimize_text(text: str, app_name: str = "") -> str:
    """
    在线程池里执行同步 HTTP 请求，避免阻塞主事件循环。
    """
    _ = app_name
    return await asyncio.to_thread(apply_if_enabled, text)

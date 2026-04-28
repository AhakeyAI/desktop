# coding: utf-8
"""
文本优化模块。

优先走当前项目的 AhaType/Typeless 链路：
1. 读取本地 typeless_config.json
2. 在 typeless_enabled + access_token 可用时，请求云端 /api/v1/typeless/process
3. 将返回的配额快照写回 typeless_config.json，供 GUI 自动刷新

若未启用 AhaType，则兼容旧版 /tmp/capswriter_config.json 的 OpenAI 兼容接口配置。
"""

from __future__ import annotations

import json
import logging
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, MutableMapping, Optional, Tuple

try:
    from util.logger import get_logger

    _logger = get_logger("client")
except Exception:
    _logger = logging.getLogger("text_optimizer")


LEGACY_CONFIG_PATH = "/tmp/capswriter_config.json"

# 与 vibe_code_config_tool.src.core.cloud_settings.DEFAULT_API_BASE 保持一致。
_FALLBACK_TYPELESS_API_BASE = "https://vibe-220629-6-1398334410.sh.run.tcloudbase.com"

SYSTEM_PROMPT_BASE = """你是一个语音转文字后处理助手。将口语化的转录文本清理为书面文本。

清理规则：
- 去除口头禅和填充词（嗯、啊、就是说、然后那个、basically、you know）
- 修正语法、拼写和标点
- 去除重复、口吃和错误起头
- 修正明显的语音识别错误
- 保留说话者的语气、措辞和意图
- 保留专业术语和专有名词

自我纠正：当说话者纠正自己（"等等不对"、"我是说"、"应该是"），只保留纠正后的版本。
语音标点：将口述标点转为符号（"句号"→。/ "逗号"→，/ "换行"→实际换行）。
数字格式化：将口述数字转为标准写法（"二零二六年一月十五号"→"2026年1月15日"）。

输出规则：
1. 只输出处理后的文本
2. 不要加任何说明、标签或前言
3. 不要添加原文中没有的内容
4. 如果输入为空或只有填充词，输出空文本"""

import re as _re

_APP_CONTEXT_RULES = [
    ("code", _re.compile(r"(cursor|code|vscode|visual studio|terminal|iterm|xcode|claude)", _re.IGNORECASE), "代码/开发工具"),
    ("email", _re.compile(r"(mail|gmail|outlook|spark|thunderbird)", _re.IGNORECASE), "邮件"),
    ("chat", _re.compile(r"(slack|discord|teams|wechat|微信|telegram|whatsapp|message|钉钉|飞书|lark)", _re.IGNORECASE), "聊天/即时通讯"),
    ("document", _re.compile(r"(notion|docs|word|pages|onenote|obsidian|typora|bear|语雀)", _re.IGNORECASE), "文档/笔记"),
]

_CONTEXT_PROMPTS = {
    "code": """
上下文提示：当前正在代码/开发工具中使用。
- 保留所有代码语法、符号、变量名和大小写
- 技术术语保持英文原文（如 function、class、import、API、JSON 等）
- 代码块和命令行内容保持原样，不做修改
- 如果用户在描述代码逻辑，保留技术准确性优先于语句通顺""",
    "email": """
上下文提示：当前正在邮件应用中使用。
- 保留邮件结构（称呼、正文、落款）
- 语气适当正式化，但保持原有的正式/随意程度
- 正确格式化收件人称呼和签名""",
    "chat": """
上下文提示：当前正在聊天/即时通讯应用中使用。
- 保持简洁和对话感
- 可以保留适度的口语化表达
- 不需要过度正式化，保持自然的聊天风格""",
    "document": """
上下文提示：当前正在文档/笔记应用中使用。
- 保留标题、列表、分段等文档结构
- 适当使用分段和换行提升可读性
- 保持逻辑连贯性和条理清晰""",
    "general": "",
}


def _truncate_for_log(text: str, limit: int = 120) -> str:
    s = (text or "").replace("\n", "\\n").strip()
    if len(s) <= limit:
        return s
    return s[: limit - 3] + "..."


def _normalize_api_base(url: str) -> str:
    u = (url or "").strip().rstrip("/")
    if not u:
        return ""
    if "://" not in u:
        u = "https://{}".format(u)
    return u


def _repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def _resolve_typeless_api_base(legacy_from_json: str = "") -> str:
    for key in ("VIBE_TYPELESS_API_BASE", "VIBE_API_BASE"):
        v = _normalize_api_base(os.environ.get(key) or "")
        if v:
            return v

    root = _repo_root()
    try:
        if str(root) not in sys.path:
            sys.path.insert(0, str(root))
        from src.core import cloud_settings as _cloud_settings

        v = _normalize_api_base(_cloud_settings.effective_api_base())
        if v:
            return v
    except Exception:
        pass

    v = _normalize_api_base(_FALLBACK_TYPELESS_API_BASE)
    if v:
        return v
    return _normalize_api_base(legacy_from_json)


def _sanitize_typeless_config_dict(d: MutableMapping[str, Any]) -> None:
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
        return datetime.fromisoformat(s).replace(tzinfo=None)
    except Exception:
        return None


def _read_legacy_config() -> Dict[str, Any]:
    try:
        if os.path.exists(LEGACY_CONFIG_PATH):
            with open(LEGACY_CONFIG_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
            return data if isinstance(data, dict) else {}
    except Exception:
        pass
    return {}


def _call_typeless_process(text: str) -> Tuple[bool, str]:
    cfg = _load_typeless_config()
    if not isinstance(cfg, dict):
        return False, text

    legacy_cfg = _read_legacy_config()
    legacy_api = (cfg.get("api_base") or legacy_cfg.get("api_base") or "").strip()
    _sanitize_typeless_config_dict(cfg)

    if not cfg.get("typeless_enabled"):
        return False, text

    valid_until = _parse_valid_until(cfg.get("token_valid_until"))
    if (valid_until is None) or (datetime.utcnow() > valid_until):
        print("[AhaType] 已开启，但剩余时间不足或 token_valid_until 无效，跳过整理", flush=True)
        return True, text

    api_base = _resolve_typeless_api_base(legacy_api)
    token = (cfg.get("access_token") or "").strip()
    if not api_base:
        print("[AhaType] 未找到可用 API 地址，跳过整理", flush=True)
        return True, text
    if not token:
        print("[AhaType] 已开启，但缺少 access_token，跳过整理", flush=True)
        return True, text

    url = f"{api_base}/api/v1/typeless/process"
    print(f"[AhaType] 请求整理: {url}", flush=True)
    t0 = time.time()
    try:
        import requests

        resp = requests.post(
            url,
            json={"text": text},
            headers={
                "Content-Type": "application/json; charset=utf-8",
                "Authorization": f"Bearer {token}",
            },
            timeout=(15, 120),
        )
        raw = resp.text
        print(f"[AhaType] 响应 HTTP {resp.status_code}", flush=True)
    except Exception as e:
        print(f"[AhaType] 网络错误: {e}", flush=True)
        return True, text

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        print(f"[AhaType] 返回非 JSON: {_truncate_for_log(raw, 200)}", flush=True)
        return True, text

    if not isinstance(data, dict):
        print("[AhaType] 返回结构异常", flush=True)
        return True, text

    if resp.status_code != 200:
        print(
            "[AhaType] HTTP 错误 {}: {}".format(
                resp.status_code,
                _truncate_for_log(raw, 200),
            ),
            flush=True,
        )
        return True, text

    biz_code = data.get("code")
    if biz_code != 0:
        print(f"[AhaType] 业务错误 code={biz_code} msg={data.get('errorMsg')!r}", flush=True)
        return True, text

    inner = data.get("data") if isinstance(data.get("data"), dict) else {}
    quota = inner.get("quota") if isinstance(inner.get("quota"), dict) else None
    out = inner.get("text") if isinstance(inner.get("text"), str) else None
    if out is None and isinstance(inner.get("result"), str):
        out = inner.get("result")

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

    elapsed = time.time() - t0
    if isinstance(out, str) and out.strip():
        result = out.strip()
        print(
            "[AhaType] 整理完成 ({:.2f}s): {} -> {}".format(
                elapsed,
                _truncate_for_log(text),
                _truncate_for_log(result),
            ),
            flush=True,
        )
        return True, result

    print(f"[AhaType] 返回成功但没有文本输出 ({elapsed:.2f}s)", flush=True)
    return True, text


def _classify_context(app_name: str) -> str:
    if not app_name:
        return "general"
    for ctx, pattern, _desc in _APP_CONTEXT_RULES:
        if pattern.search(app_name):
            return ctx
    return "general"


def _build_system_prompt(context: str = "general") -> str:
    prompt = SYSTEM_PROMPT_BASE
    extra = _CONTEXT_PROMPTS.get(context, "")
    if extra:
        prompt += "\n" + extra
    return prompt


def _optimize_cloud_legacy(
    text: str,
    api_url: str,
    api_key: str,
    model: str = "",
    context: str = "general",
) -> str:
    try:
        import httpx
    except ImportError:
        print("[AI] 错误: httpx 未安装，请运行: pip install httpx", flush=True)
        return text

    url = api_url.rstrip("/")
    if not url.endswith("/chat/completions"):
        if _re.search(r"/v\d+(/|$)", url):
            url += "/chat/completions"
        else:
            url += "/v1/chat/completions"

    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    payload = {
        "model": model or "gpt-3.5-turbo",
        "messages": [
            {"role": "system", "content": _build_system_prompt(context)},
            {"role": "user", "content": text},
        ],
        "max_tokens": len(text) * 3 + 100,
        "temperature": 0.3,
    }

    try:
        with httpx.Client(timeout=30.0) as client:
            resp = client.post(url, json=payload, headers=headers)
            resp.raise_for_status()
            data = resp.json()
            return data["choices"][0]["message"]["content"].strip()
    except Exception as e:
        print(f"[AI] 云端优化失败: {e}", flush=True)
        return text


def _apply_legacy_ai_optimize(text: str, app_name: str = "") -> str:
    cfg = _read_legacy_config()
    if not cfg.get("enable_ai_optimize", False):
        return text

    context = _classify_context(app_name)
    if context != "general":
        print(f"[AI] 上下文: {context} (应用: {app_name})", flush=True)

    api_url = cfg.get("ai_api_url", "")
    api_key = cfg.get("ai_api_key", "")
    api_model = cfg.get("ai_api_model", "")
    if not api_url:
        print("[AI] 未配置云端 API 地址，跳过优化", flush=True)
        return text

    t0 = time.time()
    result = _optimize_cloud_legacy(text, api_url, api_key, api_model, context)
    elapsed = time.time() - t0
    if result != text:
        print(f"[AI] 优化完成 ({elapsed:.2f}s): {text} -> {result}", flush=True)
    else:
        print(f"[AI] 文本无变化 ({elapsed:.2f}s)", flush=True)
    return result


def optimize_text(text: str, app_name: str = "") -> str:
    if not text or not text.strip():
        return text

    handled, result = _call_typeless_process(text)
    if handled:
        return result

    return _apply_legacy_ai_optimize(text, app_name=app_name)


def test_cloud_connection(api_url: str, api_key: str, model: str = "") -> str:
    try:
        result = _optimize_cloud_legacy("测试连接", api_url, api_key, model)
        if result and result != "测试连接":
            return f"✅ 连接成功！响应: {result}"
        if result == "测试连接":
            return "✅ 连接成功（响应与输入相同）"
        return "❌ 连接成功但返回为空"
    except Exception as e:
        return f"❌ 连接失败: {e}"

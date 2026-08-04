"""
方舟推理集成模块。

职责：
1. 以 OpenAI 兼容协议调用火山方舟 chat/completions。
2. 对上游异常做统一错误包装。
"""

from typing import Any, Dict, Tuple

import requests

import config


def chat_completions_non_stream(body: Dict[str, Any]) -> Tuple[int, Dict[str, Any]]:
    """调用方舟非流式对话接口，返回 (HTTP 状态码, JSON 响应体)。"""
    if not config.ARK_API_KEY or not config.ARK_MODEL_ID:
        return 503, {
            "error": {
                "message": "服务端未配置 ARK_API_KEY 或 ARK_MODEL_ID",
                "type": "server_error",
            }
        }

    url = "{}/chat/completions".format(config.ARK_BASE_URL.rstrip("/"))
    outbound = {
        "model": config.ARK_MODEL_ID,
        "messages": body.get("messages"),
    }
    if "temperature" in body:
        outbound["temperature"] = body["temperature"]
    if "max_tokens" in body:
        outbound["max_tokens"] = body["max_tokens"]
    if "top_p" in body:
        outbound["top_p"] = body["top_p"]
    if body.get("stream"):
        return 400, {
            "error": {
                "message": "当前仅支持非流式，请勿设置 stream 或传 stream=false",
                "type": "invalid_request_error",
            }
        }
    outbound["stream"] = False

    headers = {
        "Authorization": "Bearer {}".format(config.ARK_API_KEY),
        "Content-Type": "application/json",
    }

    try:
        r = requests.post(url, json=outbound, headers=headers, timeout=120)
        try:
            data = r.json()
        except Exception:
            data = {
                "error": {
                    "message": (r.text[:500] if r.text else "invalid json from upstream"),
                    "type": "upstream_error",
                }
            }
        return r.status_code, data
    except requests.RequestException as e:
        return 502, {
            "error": {
                "message": "上游请求失败: {}".format(e),
                "type": "upstream_error",
            }
        }

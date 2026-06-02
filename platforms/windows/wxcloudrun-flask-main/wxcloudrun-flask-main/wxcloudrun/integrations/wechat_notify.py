"""
微信支付回调解密模块。

职责：
1. 读取 API v3 密钥。
2. 解密微信回调中的 resource 字段。
"""

import base64
import os
from typing import Any, Dict, Optional

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


def _api_v3_key() -> str:
    """读取微信 API v3 密钥。"""
    return os.environ.get("WECHAT_PAY_API_V3_KEY", "").strip()


def is_notify_configured() -> bool:
    """检查回调解密密钥是否配置完成。"""
    return len(_api_v3_key()) == 32


def decrypt_notify_resource(body: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """解密微信支付回调 resource，成功返回 dict，失败返回 None。"""
    if not isinstance(body, dict):
        return None

    resource = body.get("resource") or {}
    if not isinstance(resource, dict):
        return None

    if resource.get("algorithm") != "AEAD_AES_256_GCM":
        return None

    nonce = (resource.get("nonce") or "").strip()
    ciphertext_b64 = (resource.get("ciphertext") or "").strip()
    associated_data = (resource.get("associated_data") or "").strip()
    key = _api_v3_key()

    if not key or not nonce or not ciphertext_b64:
        return None

    try:
        aesgcm = AESGCM(key.encode("utf-8"))
        plaintext = aesgcm.decrypt(
            nonce.encode("utf-8"),
            base64.b64decode(ciphertext_b64),
            associated_data.encode("utf-8") if associated_data else None,
        )

        import json

        data = json.loads(plaintext.decode("utf-8"))
        return data if isinstance(data, dict) else None
    except Exception:
        return None

"""
微信 Native 下单集成模块。

职责：
1. 读取微信支付配置。
2. 构建并签名 Native 下单请求。
3. 返回 code_url 供前端扫码支付。
"""

from __future__ import annotations

import base64
import json
import os
import time
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

NATIVE_POST_PATH = "/v3/pay/transactions/native"
NATIVE_URL = "https://api.mch.weixin.qq.com" + NATIVE_POST_PATH


def _cfg() -> Dict[str, str]:
    """读取微信支付配置。"""
    return {
        "appid": os.environ.get("WECHAT_PAY_APPID", "").strip(),
        "mchid": os.environ.get("WECHAT_PAY_MCHID", "").strip(),
        "serial_no": os.environ.get("WECHAT_PAY_SERIAL_NO", "").strip(),
        "key_path": os.environ.get("WECHAT_PAY_PRIVATE_KEY_PATH", "").strip(),
        "notify_url": os.environ.get("WECHAT_PAY_NOTIFY_URL", "").strip(),
    }


def is_configured() -> bool:
    """检查微信 Native 下单所需配置是否齐全。"""
    c = _cfg()
    return all(c[k] for k in ("appid", "mchid", "serial_no", "key_path", "notify_url"))


def _load_private_key():
    """加载商户私钥文件。"""
    path = Path(_cfg()["key_path"])
    if not path.is_file():
        return None
    return serialization.load_pem_private_key(path.read_bytes(), password=None)


def _authorization(private_key, mchid: str, serial_no: str, body_str: str) -> str:
    """构建微信支付 API v3 Authorization 头。"""
    import secrets

    ts = str(int(time.time()))
    nonce = secrets.token_hex(16)
    message = "POST\n{}\n{}\n{}\n{}\n".format(NATIVE_POST_PATH, ts, nonce, body_str)
    sig = private_key.sign(message.encode("utf-8"), padding.PKCS1v15(), hashes.SHA256())
    sign_b64 = base64.b64encode(sig).decode("ascii")
    token = 'mchid="{}",nonce_str="{}",timestamp="{}",serial_no="{}",signature="{}"'.format(
        mchid, nonce, ts, serial_no, sign_b64
    )
    return "WECHATPAY2-SHA256-RSA2048 {}".format(token)


def create_native_order(
    *,
    out_trade_no: str,
    description: str,
    amount_fen: int,
) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    """调用微信 Native 下单接口，返回 (响应体, 错误信息)。"""
    if not is_configured():
        return None, "服务端未配置微信 Native 支付（请检查 WECHAT_PAY_* 环境变量）"

    c = _cfg()
    key = _load_private_key()
    if key is None:
        return None, "无法读取商户私钥文件: {}".format(c["key_path"])

    body = {
        "appid": c["appid"],
        "mchid": c["mchid"],
        "description": description[:127],
        "out_trade_no": out_trade_no,
        "notify_url": c["notify_url"],
        "amount": {"total": int(amount_fen), "currency": "CNY"},
    }
    body_str = json.dumps(body, ensure_ascii=False, separators=(",", ":"))

    auth = _authorization(key, c["mchid"], c["serial_no"], body_str)
    headers = {
        "Authorization": auth,
        "Accept": "application/json",
        "Content-Type": "application/json; charset=utf-8",
    }

    try:
        r = requests.post(NATIVE_URL, data=body_str.encode("utf-8"), headers=headers, timeout=30)
        try:
            data = r.json()
        except Exception:
            return None, "微信返回非 JSON: {}".format((r.text or "")[:200])
    except requests.RequestException as e:
        return None, "请求微信支付失败: {}".format(e)

    if r.status_code != 200:
        msg = data.get("message") if isinstance(data, dict) else str(data)
        return None, "微信支付错误({}): {}".format(r.status_code, msg)

    if not isinstance(data, dict) or "code_url" not in data:
        return None, "微信响应缺少 code_url"

    return data, None

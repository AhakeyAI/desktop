"""调用微信云托管上的 API v1。"""

from typing import Any, Dict, Optional, Tuple

import requests

# (连接超时秒, 读取超时秒) — 云托管冷启动时读响应可能超过 30s
API_TIMEOUT: Tuple[int, int] = (15, 90)


class CloudApiError(Exception):
    def __init__(self, message: str, status_code: Optional[int] = None):
        super().__init__(message)
        self.status_code = status_code


def _is_success_code(code: Any) -> bool:
    return str(code) in {"0", "200"}


def _response_message(data: Any, fallback: str) -> str:
    if isinstance(data, dict):
        for key in ("errorMsg", "msg", "message", "error"):
            value = data.get(key)
            if value:
                return str(value)
    return fallback


def _normalize_profile(data: Dict[str, Any]) -> Dict[str, Any]:
    out = dict(data or {})
    for snake, camel in (
        ("id", "userId"),
        ("user_id", "userId"),
        ("token_valid_until", "tokenValidUntil"),
        ("limit_daily", "limitDaily"),
        ("limit_weekly", "limitWeekly"),
        ("limit_monthly", "limitMonthly"),
        ("used_daily", "usedDaily"),
        ("used_weekly", "usedWeekly"),
        ("used_monthly", "usedMonthly"),
    ):
        if snake not in out and camel in out:
            out[snake] = out.get(camel)
    policy = out.get("policy")
    if isinstance(policy, dict):
        policy = dict(policy)
        for snake, camel in (
            ("recharge_prices_fen", "rechargePricesFen"),
            ("default_limit_daily", "defaultLimitDaily"),
            ("default_limit_weekly", "defaultLimitWeekly"),
            ("default_limit_monthly", "defaultLimitMonthly"),
            ("enable_daily", "enableDaily"),
            ("enable_weekly", "enableWeekly"),
            ("enable_monthly", "enableMonthly"),
        ):
            if snake not in policy and camel in policy:
                policy[snake] = policy.get(camel)
        out["policy"] = policy
    return out


class CloudApi:
    def __init__(self, base_url: str, access_token: Optional[str] = None):
        self.base_url = base_url.rstrip("/")
        self.access_token = access_token

    def _url(self, path: str) -> str:
        return "{}/{}".format(self.base_url, path.lstrip("/"))

    def _json_headers(self) -> Dict[str, str]:
        h = {"Content-Type": "application/json"}
        if self.access_token:
            h["Authorization"] = "Bearer {}".format(self.access_token)
        return h

    def login(self, phone: str, password: str) -> str:
        r = requests.post(
            self._url("api/v1/auth/login"),
            json={"phone": phone, "password": password},
            headers={"Content-Type": "application/json"},
            timeout=API_TIMEOUT,
        )
        try:
            data = r.json()
        except Exception:
            raise CloudApiError("服务器返回非 JSON", r.status_code)
        if not _is_success_code(data.get("code")):
            raise CloudApiError(_response_message(data, "登录失败"), r.status_code)
        inner = data.get("data") or {}
        return inner.get("access_token") or inner.get("token") or ""

    def register(self, phone: str, password: str) -> str:
        r = requests.post(
            self._url("api/v1/auth/register"),
            json={"phone": phone, "password": password},
            headers={"Content-Type": "application/json"},
            timeout=API_TIMEOUT,
        )
        try:
            data = r.json()
        except Exception:
            raise CloudApiError("服务器返回非 JSON", r.status_code)
        if not _is_success_code(data.get("code")):
            raise CloudApiError(_response_message(data, "注册失败"), r.status_code)
        inner = data.get("data") or {}
        return inner.get("access_token") or inner.get("token") or ""

    def users_me(self) -> Dict[str, Any]:
        r = requests.get(
            self._url("api/v1/auth/users/me"),
            headers=self._json_headers(),
            timeout=API_TIMEOUT,
        )
        try:
            data = r.json()
        except Exception:
            raise CloudApiError("服务器返回非 JSON", r.status_code)
        if r.status_code != 200:
            raise CloudApiError(
                _response_message(data, "请求失败"),
                r.status_code,
            )
        if not _is_success_code(data.get("code")):
            raise CloudApiError(_response_message(data, "获取用户信息失败"), r.status_code)
        return _normalize_profile(data.get("data") or {})

    def coupon_redeem(self, code: str) -> Dict[str, Any]:
        r = requests.post(
            self._url("api/v1/coupon/redeem"),
            json={"code": code},
            headers=self._json_headers(),
            timeout=API_TIMEOUT,
        )
        try:
            data = r.json()
        except Exception:
            raise CloudApiError("服务器返回非 JSON", r.status_code)
        if r.status_code != 200:
            raise CloudApiError(
                _response_message(data, "兑换失败"),
                r.status_code,
            )
        if not _is_success_code(data.get("code")):
            raise CloudApiError(_response_message(data, "兑换失败"), r.status_code)
        return data.get("data") or {}

    def payment_wechat_native(self, plan: Optional[str] = None) -> Dict[str, Any]:
        """
        微信 Native 下单（服务端实现）。
        期望返回 data 中含 code_url（或 h5_url）供唤起支付。
        """
        body: Dict[str, Any] = {}
        if plan:
            body["plan"] = plan
        r = requests.post(
            self._url("api/v1/payment/wechat/native"),
            json=body,
            headers=self._json_headers(),
            timeout=60,
        )
        try:
            data = r.json()
        except Exception:
            raise CloudApiError("服务器返回非 JSON", r.status_code)
        if not _is_success_code(data.get("code")):
            raise CloudApiError(_response_message(data, "创建支付订单失败"), r.status_code)
        return data.get("data") or {}

    def config_tool_check_release(self, current_version: str) -> Dict[str, Any]:
        """
        检查键盘配置工具是否有新版本（无需登录）。

        返回 data 含 has_update, latest_version, release_notes, download_url。
        """
        r = requests.get(
            self._url("api/v1/client/config-tool/release"),
            params={"current_version": current_version},
            headers={"Content-Type": "application/json"},
            timeout=(5, 25),
        )
        try:
            data = r.json()
        except Exception:
            raise CloudApiError("服务器返回非 JSON", r.status_code)
        if r.status_code != 200:
            raise CloudApiError(
                _response_message(data, "检查更新失败"),
                r.status_code,
            )
        if not _is_success_code(data.get("code")):
            raise CloudApiError(_response_message(data, "检查更新失败"), r.status_code)
        return data.get("data") or {}

    def payment_wechat_order_status(self, out_trade_no: str) -> Dict[str, Any]:
        r = requests.get(
            self._url("api/v1/payment/wechat/order-status"),
            params={"outTradeNo": out_trade_no},
            headers=self._json_headers(),
            timeout=API_TIMEOUT,
        )
        try:
            data = r.json()
        except Exception:
            raise CloudApiError("服务器返回非 JSON", r.status_code)
        if r.status_code != 200:
            raise CloudApiError(
                _response_message(data, "查询失败"),
                r.status_code,
            )
        if not _is_success_code(data.get("code")):
            raise CloudApiError(_response_message(data, "查询失败"), r.status_code)
        return data.get("data") or {}

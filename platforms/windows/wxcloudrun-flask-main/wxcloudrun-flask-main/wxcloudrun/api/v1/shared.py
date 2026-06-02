"""
API v1 共享上下文与工具模块。

职责：
1. 提供统一的 Blueprint 实例。
2. 承载跨路由复用的常量与鉴权/兑换码辅助函数。
3. 避免各业务路由模块重复定义通用逻辑。
"""

import hashlib
import logging
import re
import secrets
import threading
from datetime import datetime, timedelta
from typing import Any, Dict, Optional, Tuple, Union

from flask import Blueprint, request

import config
from wxcloudrun.extensions import db
from wxcloudrun.models import QuotaPolicy, User
from wxcloudrun.response import make_err_response
from wxcloudrun.services.auth_service import decode_access_token, is_admin_phone
from wxcloudrun.services.quota_service import get_or_create_policy, sync_user_periods

bp = Blueprint("api_v1", __name__, url_prefix="/api/v1")
logger = logging.getLogger("wxcloudrun.api_v1")

PHONE_RE = re.compile(r"^1\d{10}$")
RECHARGE_PLAN_MAP = {
    "monthly": ("包月充值", "recharge_monthly_fen"),
    "quarterly": ("包季充值", "recharge_quarterly_fen"),
    "yearly": ("包年充值", "recharge_yearly_fen"),
}
PLAN_DAYS = {"monthly": 30, "quarterly": 90, "yearly": 365}
COUPON_CODE_RE = re.compile(r"^[A-Z2-9]{4}(?:-[A-Z2-9]{4}){3}$")
COUPON_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
SYSTEM_PROMPT_BASE = """你是ASR文本转述器，不是问答助手。\n"
        "核心目标：把用户原话转述成更清晰的文本，第一优先级是忠实保留原意。\n"
        "处理原则（按优先级）：\n"
        "1) 忠实转述优先：不得改变用户意图，不得补充新需求，不得替用户下结论。\n"
        "2) 轻度优化：只做必要的语病修正、口头词清理、标点整理；不要过度重写。\n"
        "3) 禁止代答：即使输入像提问，也只改写该提问，不要回答问题本身。\n"
        "4) 技术内容保真：术语、变量名、路径、命令、版本号、报错原样保留，精准识别并修正技术词汇（如：PyTorch, OpenCV, Cython, SLAM, DROID-SLAM, Ubuntu, BLE, TCP, ROS, Point Cloud 等）\n"
        "5) 符号恢复：在技术上下文中将口语符号词恢复为真实符号。\n"
        "6) 符号映射：下划线/underscore->_，斜杠/slash->/，反斜杠/backslash->\\\\，点/dot->.，中划线/杠/dash/hyphen->-，冒号/colon->:，逗号/comma->,。\n"
        "7) 输出仅一段最终改写文本，不要解释、不要前后缀。\n"
        "8) 输出语言跟随输入：中文为主则输出中文；英文技术内容保持原样。\n"
        "9) 最终输出若仍包含第一人称，继续改写直到不含第一人称为止。\n"""

# 兑换码失败次数（按用户 id，进程内内存；多实例部署建议改为 Redis）。
_coupon_redeem_lock = threading.Lock()
_coupon_redeem_state: Dict[int, Dict[str, Any]] = {}


def coupon_redeem_lockout_message(user_id: int) -> Optional[str]:
    """若用户仍在兑换冷却期，返回错误文案；否则返回 None。"""
    now = datetime.utcnow()
    with _coupon_redeem_lock:
        state = _coupon_redeem_state.get(user_id)
        if not state:
            return None
        locked_until = state.get("locked_until")
        if not isinstance(locked_until, datetime):
            return None
        if now < locked_until:
            remaining = int((locked_until - now).total_seconds())
            mins = max(1, (remaining + 59) // 60)
            return "兑换尝试过于频繁，请在约 {} 分钟后再试".format(mins)
        state["locked_until"] = None
        state["failures"] = []
    return None


def coupon_redeem_record_failure(user_id: int) -> None:
    """记录一次兑换失败，并在达到阈值后触发临时锁定。"""
    window = timedelta(minutes=config.COUPON_REDEEM_WINDOW_MINUTES)
    max_fails = max(1, config.COUPON_REDEEM_MAX_FAILS)
    lockout = timedelta(minutes=config.COUPON_REDEEM_LOCKOUT_MINUTES)
    now = datetime.utcnow()
    with _coupon_redeem_lock:
        state = _coupon_redeem_state.setdefault(user_id, {"failures": [], "locked_until": None})
        failures = state.get("failures")
        if not isinstance(failures, list):
            failures = []
            state["failures"] = failures
        failures[:] = [x for x in failures if isinstance(x, datetime) and now - x <= window]
        failures.append(now)
        if len(failures) >= max_fails:
            state["locked_until"] = now + lockout
            state["failures"] = []


def coupon_redeem_clear_success(user_id: int) -> None:
    """兑换成功后清理该用户的失败记录。"""
    with _coupon_redeem_lock:
        _coupon_redeem_state.pop(user_id, None)


def policy_recharge_prices_fen(policy: QuotaPolicy) -> dict:
    """返回当前策略下的套餐价格（单位：分）。"""
    return {
        "monthly": int(policy.recharge_monthly_fen),
        "quarterly": int(policy.recharge_quarterly_fen),
        "yearly": int(policy.recharge_yearly_fen),
    }


def normalize_coupon_code(code: str) -> str:
    """标准化兑换码格式，合法时返回 XXXX-XXXX-XXXX-XXXX。"""
    s = (code or "").strip().upper()
    s = re.sub(r"[^A-Z0-9]", "", s)
    if len(s) != 16:
        return ""
    return "{}-{}-{}-{}".format(s[0:4], s[4:8], s[8:12], s[12:16])


def coupon_code_hash(code: str) -> str:
    """对兑换码执行加盐哈希，返回十六进制摘要。"""
    normalized = normalize_coupon_code(code)
    if not normalized:
        return ""
    raw = "{}|{}".format(config.COUPON_CODE_PEPPER, normalized).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def generate_coupon_code() -> str:
    """生成符合规则的兑换码明文。"""
    while True:
        chars = "".join(secrets.choice(COUPON_ALPHABET) for _ in range(16))
        code = "{}-{}-{}-{}".format(chars[0:4], chars[4:8], chars[8:12], chars[12:16])
        if COUPON_CODE_RE.match(code):
            return code


def db_err_detail(exc: Exception, max_len: int = 480) -> str:
    """提取数据库异常详情并限制最大长度。"""
    parts = [str(exc).strip()]
    origin = getattr(exc, "orig", None)
    if origin is not None:
        parts.append(str(origin).strip())
    msg = " | ".join(x for x in parts if x)
    if len(msg) <= max_len:
        return msg
    return msg[: max_len - 3] + "..."


def bearer_token() -> Optional[str]:
    """从 Authorization 头中提取 Bearer token。"""
    header = request.headers.get("Authorization", "")
    if header.startswith("Bearer "):
        return header[7:].strip() or None
    return None


def current_user_optional() -> Optional[User]:
    """尝试获取当前登录用户，失败时返回 None。"""
    token = bearer_token()
    if not token:
        return None
    payload = decode_access_token(token)
    if not payload or "sub" not in payload:
        return None
    try:
        uid = int(payload["sub"])
    except (TypeError, ValueError):
        return None
    return User.query.get(uid)


def require_user() -> Union[User, Tuple]:
    """要求当前请求已登录，失败时返回统一错误响应。"""
    user = current_user_optional()
    if not user:
        return make_err_response("未登录或令牌无效"), 401
    return user


def require_admin() -> Union[User, Tuple]:
    """要求当前请求为管理员，失败时返回统一错误响应。"""
    user = current_user_optional()
    if not user:
        return make_err_response("未登录或令牌无效"), 401
    if not is_admin_phone(user.phone):
        return make_err_response("需要管理员权限"), 403
    return user


def user_me_payload(user: User, policy: QuotaPolicy) -> dict:
    """构建 `/users/me` 场景下的统一用户信息返回体。"""
    sync_user_periods(user)
    db.session.add(user)
    db.session.commit()
    return {
        "phone": user.phone,
        "is_admin": is_admin_phone(user.phone),
        "token_valid_until": (
            user.token_valid_until.strftime("%Y-%m-%d %H:%M:%S")
            if user.token_valid_until
            else None
        ),
        "limit_daily": user.limit_daily,
        "limit_weekly": user.limit_weekly,
        "limit_monthly": user.limit_monthly,
        "used_daily": user.used_daily,
        "used_weekly": user.used_weekly,
        "used_monthly": user.used_monthly,
        "policy": {
            "enable_daily": policy.enable_daily,
            "enable_weekly": policy.enable_weekly,
            "enable_monthly": policy.enable_monthly,
            "default_limit_daily": policy.default_limit_daily,
            "default_limit_weekly": policy.default_limit_weekly,
            "default_limit_monthly": policy.default_limit_monthly,
            "recharge_prices_fen": policy_recharge_prices_fen(policy),
        },
    }


__all__ = [
    "bp",
    "logger",
    "PHONE_RE",
    "RECHARGE_PLAN_MAP",
    "PLAN_DAYS",
    "SYSTEM_PROMPT_BASE",
    "db",
    "get_or_create_policy",
    "require_user",
    "require_admin",
    "user_me_payload",
    "normalize_coupon_code",
    "coupon_code_hash",
    "generate_coupon_code",
    "coupon_redeem_lockout_message",
    "coupon_redeem_record_failure",
    "coupon_redeem_clear_success",
    "db_err_detail",
]


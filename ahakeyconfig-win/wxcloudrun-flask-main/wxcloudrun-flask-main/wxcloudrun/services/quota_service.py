"""
配额服务模块。

职责：
1. 同步用户日/周/月周期。
2. 校验推理请求是否超额。
3. 按 token 消耗更新用户用量。
4. 获取或初始化全局配额策略。
"""

from datetime import datetime, timezone
from typing import Tuple

from wxcloudrun.extensions import db
from wxcloudrun.models import QuotaPolicy, User


def _utc_today() -> str:
    """返回 UTC 日期键（YYYY-MM-DD）。"""
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def _utc_iso_week() -> str:
    """返回 UTC ISO 周键（YYYY-Www）。"""
    d = datetime.now(timezone.utc).date()
    y, w, _ = d.isocalendar()
    return f"{y}-W{w:02d}"


def _utc_month() -> str:
    """返回 UTC 月份键（YYYY-MM）。"""
    return datetime.now(timezone.utc).strftime("%Y-%m")


def sync_user_periods(user: User) -> None:
    """同步用户周期并在跨周期时自动清零对应用量。"""
    today = _utc_today()
    week = _utc_iso_week()
    month = _utc_month()
    changed = False

    if user.daily_period_key != today:
        user.daily_period_key = today
        user.used_daily = 0
        changed = True
    if user.weekly_period_key != week:
        user.weekly_period_key = week
        user.used_weekly = 0
        changed = True
    if user.monthly_period_key != month:
        user.monthly_period_key = month
        user.used_monthly = 0
        changed = True

    if changed:
        db.session.add(user)


def check_quotas_before_inference(user: User, policy: QuotaPolicy) -> Tuple[bool, str]:
    """在推理前检查有效期与配额限制。"""
    sync_user_periods(user)

    if user.token_valid_until and datetime.utcnow() > user.token_valid_until:
        return False, "订阅已过期，请先续费"

    if policy.enable_daily and user.limit_daily > 0 and user.used_daily >= user.limit_daily:
        return False, "已达到每日额度上限"

    if policy.enable_weekly and user.limit_weekly > 0 and user.used_weekly >= user.limit_weekly:
        return False, "已达到每周额度上限"

    if policy.enable_monthly and user.limit_monthly > 0 and user.used_monthly >= user.limit_monthly:
        return False, "已达到每月额度上限"

    return True, ""


def apply_token_usage(user: User, policy: QuotaPolicy, total_tokens: int) -> None:
    """按本次请求 token 用量累加用户统计。"""
    _ = policy
    if total_tokens <= 0:
        return

    sync_user_periods(user)
    user.used_daily += total_tokens
    user.used_weekly += total_tokens
    user.used_monthly += total_tokens
    db.session.add(user)


def get_or_create_policy() -> QuotaPolicy:
    """获取全局策略，若不存在则创建默认策略。"""
    p = QuotaPolicy.query.get(1)
    if p is None:
        p = QuotaPolicy(id=1)
        db.session.add(p)
        db.session.commit()
    return p

"""
API v1 - 管理域路由。

包含：
1. 配额策略查询与更新。
2. 兑换码批量生成。
"""

import secrets
import time
from datetime import datetime

from flask import request

import config
from wxcloudrun.models import CouponCode, User
from wxcloudrun.response import make_err_response, make_succ_response
from wxcloudrun.api.v1.shared import (
    bp,
    coupon_code_hash,
    generate_coupon_code,
    get_or_create_policy,
    logger,
    require_admin,
    db,
)


@bp.route("/admin/quota-policy", methods=["GET"])
def admin_quota_policy_get():
    """获取全局配额策略。"""
    result = require_admin()
    if isinstance(result, tuple):
        return result[0], result[1]

    policy = get_or_create_policy()
    return make_succ_response(
        {
            "enable_daily": policy.enable_daily,
            "enable_weekly": policy.enable_weekly,
            "enable_monthly": policy.enable_monthly,
            "default_limit_daily": policy.default_limit_daily,
            "default_limit_weekly": policy.default_limit_weekly,
            "default_limit_monthly": policy.default_limit_monthly,
            "recharge_monthly_fen": policy.recharge_monthly_fen,
            "recharge_quarterly_fen": policy.recharge_quarterly_fen,
            "recharge_yearly_fen": policy.recharge_yearly_fen,
        }
    )


@bp.route("/admin/quota-policy", methods=["PUT"])
def admin_quota_policy_put():
    """更新全局配额策略，并同步所有用户的配额上限。"""
    result = require_admin()
    if isinstance(result, tuple):
        return result[0], result[1]

    data = request.get_json(silent=True) or {}
    policy = get_or_create_policy()
    for key in ("enable_daily", "enable_weekly", "enable_monthly"):
        if key in data:
            setattr(policy, key, bool(data[key]))
    for key in (
        "default_limit_daily",
        "default_limit_weekly",
        "default_limit_monthly",
        "recharge_monthly_fen",
        "recharge_quarterly_fen",
        "recharge_yearly_fen",
    ):
        if key in data:
            setattr(policy, key, int(data[key]))
    db.session.add(policy)
    db.session.commit()

    db.session.query(User).update(
        {
            User.limit_daily: policy.default_limit_daily,
            User.limit_weekly: policy.default_limit_weekly,
            User.limit_monthly: policy.default_limit_monthly,
        }
    )
    db.session.commit()
    return make_succ_response(
        {
            "enable_daily": policy.enable_daily,
            "enable_weekly": policy.enable_weekly,
            "enable_monthly": policy.enable_monthly,
            "default_limit_daily": policy.default_limit_daily,
            "default_limit_weekly": policy.default_limit_weekly,
            "default_limit_monthly": policy.default_limit_monthly,
            "recharge_monthly_fen": policy.recharge_monthly_fen,
            "recharge_quarterly_fen": policy.recharge_quarterly_fen,
            "recharge_yearly_fen": policy.recharge_yearly_fen,
        }
    )


@bp.route("/admin/coupons/batch-create", methods=["POST"])
def admin_coupons_batch_create():
    """批量生成兑换码。"""
    result = require_admin()
    if isinstance(result, tuple):
        return result[0], result[1]
    admin_user = result

    data = request.get_json(silent=True) or {}
    try:
        count = int(data.get("count", 1))
    except (TypeError, ValueError):
        return make_err_response("count 必须是整数")
    if count < 1 or count > 500:
        return make_err_response("count 需在 1~500 之间")

    batch_id = "coupon_{}_{}".format(int(time.time()), secrets.token_hex(4))
    days = int(config.FREE_COUPON_DAYS or 60)
    now = datetime.utcnow()

    codes = []
    records = []
    local_hashes = set()
    max_attempts = count * 20
    attempts = 0
    while len(codes) < count and attempts < max_attempts:
        attempts += 1
        code = generate_coupon_code()
        code_hash = coupon_code_hash(code)
        if not code_hash or code_hash in local_hashes:
            continue
        exists = CouponCode.query.filter(CouponCode.code_hash == code_hash).first()
        if exists:
            continue
        local_hashes.add(code_hash)
        codes.append(code)
        records.append(
            CouponCode(
                code_hash=code_hash,
                benefit_days=days,
                expires_at=None,
                disabled=False,
                created_by_admin_phone=admin_user.phone,
                batch_id=batch_id,
            )
        )

    if len(codes) != count:
        return make_err_response("生成兑换码失败，请重试"), 500

    try:
        for record in records:
            db.session.add(record)
        db.session.commit()
    except Exception as exc:
        db.session.rollback()
        logger.exception("coupon batch create error: %s", exc)
        return make_err_response("写入兑换码失败"), 500

    return make_succ_response(
        {
            "batch_id": batch_id,
            "count": count,
            "benefit_days": days,
            "created_at": now.strftime("%Y-%m-%d %H:%M:%S"),
            "codes": codes,
        }
    )


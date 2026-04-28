"""
API v1 - 兑换码域路由。

包含：
1. 用户兑换码兑换。
2. 兑换失败频率控制。
"""

from datetime import datetime, timedelta

import config
from flask import request

from wxcloudrun.models import CouponCode, User
from wxcloudrun.response import make_err_response, make_succ_response
from wxcloudrun.api.v1.shared import (
    bp,
    coupon_code_hash,
    coupon_redeem_clear_success,
    coupon_redeem_lockout_message,
    coupon_redeem_record_failure,
    db,
    get_or_create_policy,
    logger,
    normalize_coupon_code,
    require_user,
    user_me_payload,
)


@bp.route("/coupon/redeem", methods=["POST"])
def coupon_redeem():
    """兑换单个兑换码并延长用户有效期。"""
    result = require_user()
    if isinstance(result, tuple):
        return result[0], result[1]
    user = result

    lock_msg = coupon_redeem_lockout_message(user.id)
    if lock_msg:
        return make_err_response(lock_msg), 429

    data = request.get_json(silent=True) or {}
    code = normalize_coupon_code(data.get("code") or "")
    if not code:
        coupon_redeem_record_failure(user.id)
        return make_err_response("兑换码格式不正确")

    code_hash = coupon_code_hash(code)
    if not code_hash:
        coupon_redeem_record_failure(user.id)
        return make_err_response("兑换码格式不正确")

    try:
        now = datetime.utcnow()
        coupon = CouponCode.query.filter(CouponCode.code_hash == code_hash).with_for_update().first()
        if not coupon:
            coupon_redeem_record_failure(user.id)
            return make_err_response("兑换码无效"), 404
        if coupon.disabled:
            coupon_redeem_record_failure(user.id)
            return make_err_response("兑换码已停用")
        if coupon.used_at is not None:
            coupon_redeem_record_failure(user.id)
            return make_err_response("兑换码已被使用")
        if coupon.expires_at and coupon.expires_at <= now:
            coupon_redeem_record_failure(user.id)
            return make_err_response("兑换码已过期")

        locked_user = User.query.filter(User.id == user.id).with_for_update().first()
        if not locked_user:
            return make_err_response("用户不存在"), 404

        days = int(coupon.benefit_days or config.FREE_COUPON_DAYS or 60)
        base = (
            locked_user.token_valid_until
            if locked_user.token_valid_until and locked_user.token_valid_until > now
            else now
        )
        locked_user.token_valid_until = base + timedelta(days=days)
        coupon.used_by_user_id = locked_user.id
        coupon.used_at = now

        db.session.add(locked_user)
        db.session.add(coupon)
        db.session.commit()
        coupon_redeem_clear_success(user.id)

        policy = get_or_create_policy()
        return make_succ_response(user_me_payload(locked_user, policy))
    except Exception as exc:
        db.session.rollback()
        logger.exception("coupon redeem error: %s", exc)
        return make_err_response("兑换失败，请稍后再试"), 500


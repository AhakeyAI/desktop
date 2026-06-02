"""
API v1 - 支付域路由。

包含：
1. 微信 Native 下单。
2. 订单状态查询。
3. 微信支付回调处理。
"""

import secrets
import time
from datetime import datetime, timedelta

from flask import jsonify, request

from wxcloudrun.integrations.wechat_native import create_native_order
from wxcloudrun.integrations.wechat_notify import decrypt_notify_resource, is_notify_configured
from wxcloudrun.models import PaymentOrder, User
from wxcloudrun.response import make_err_response, make_succ_response
from wxcloudrun.api.v1.shared import (
    PLAN_DAYS,
    RECHARGE_PLAN_MAP,
    bp,
    db,
    get_or_create_policy,
    logger,
    require_user,
)


@bp.route("/payment/wechat/order-status", methods=["GET"])
def payment_wechat_order_status():
    """查询当前用户自己的支付订单状态。"""
    result = require_user()
    if isinstance(result, tuple):
        return result[0], result[1]
    user = result

    out_trade_no = (request.args.get("out_trade_no") or "").strip()
    if not out_trade_no:
        return make_err_response("缺少 out_trade_no"), 400

    order = (
        PaymentOrder.query.filter(
            PaymentOrder.out_trade_no == out_trade_no,
            PaymentOrder.user_id == user.id,
        ).first()
    )
    if not order:
        return make_err_response("订单不存在"), 404
    return make_succ_response({"status": order.status})


@bp.route("/payment/wechat/native", methods=["POST"])
def payment_wechat_native():
    """微信 Native 下单，返回 code_url 给客户端拉起支付。"""
    result = require_user()
    if isinstance(result, tuple):
        return result[0], result[1]
    user = result

    data = request.get_json(silent=True) or {}
    plan = (data.get("plan") or "monthly").strip().lower()
    if plan not in RECHARGE_PLAN_MAP:
        return make_err_response("套餐类型非法，应为 monthly/quarterly/yearly")

    policy = get_or_create_policy()
    plan_desc, amount_field = RECHARGE_PLAN_MAP[plan]
    amount = int(getattr(policy, amount_field))
    if amount < 1 or amount > 100_000_000:
        return make_err_response("金额不合法")

    out_trade_no = "vk_{}_{}_{}".format(user.id, int(time.time()), secrets.token_hex(4))
    desc = (data.get("description") or plan_desc).strip() or plan_desc

    order = PaymentOrder(
        out_trade_no=out_trade_no,
        user_id=user.id,
        plan=plan,
        amount_fen=amount,
        status="pending",
    )
    db.session.add(order)
    db.session.commit()

    wx_body, err = create_native_order(out_trade_no=out_trade_no, description=desc, amount_fen=amount)
    if err:
        order.status = "failed"
        db.session.add(order)
        db.session.commit()
        return make_err_response(err), 503

    return make_succ_response(
        {
            "code_url": wx_body.get("code_url"),
            "out_trade_no": out_trade_no,
            "prepay_id": wx_body.get("prepay_id"),
            "plan": plan,
            "amount_fen": amount,
        }
    )


def _wechat_notify_ok():
    return jsonify({"code": "SUCCESS", "message": "成功"}), 200


def _wechat_notify_fail(msg: str):
    return jsonify({"code": "FAIL", "message": msg[:64]}), 500


@bp.route("/payment/wechat/notify", methods=["POST"])
def payment_wechat_notify():
    """处理微信支付回调并幂等更新订单与用户权益。"""
    if not is_notify_configured():
        return _wechat_notify_fail("未配置 WECHAT_PAY_API_V3_KEY")

    try:
        body = request.get_json(silent=True) or {}
        notify = decrypt_notify_resource(body)
        if not notify:
            return _wechat_notify_fail("回调解密失败")

        trade_state = (notify.get("trade_state") or "").strip().upper()
        out_trade_no = (notify.get("out_trade_no") or "").strip()
        transaction_id = (notify.get("transaction_id") or "").strip()
        if not out_trade_no:
            return _wechat_notify_fail("缺少 out_trade_no")
        if trade_state != "SUCCESS":
            return _wechat_notify_ok()

        order = (
            PaymentOrder.query.filter(PaymentOrder.out_trade_no == out_trade_no)
            .with_for_update()
            .first()
        )
        if not order:
            return _wechat_notify_fail("本地订单不存在")
        if order.status == "paid":
            return _wechat_notify_ok()

        user = User.query.filter(User.id == order.user_id).with_for_update().first()
        if not user:
            return _wechat_notify_fail("用户不存在")

        plan_days = PLAN_DAYS.get(order.plan)
        if not plan_days:
            return _wechat_notify_fail("订单套餐非法")

        now = datetime.utcnow()
        base = user.token_valid_until if user.token_valid_until and user.token_valid_until > now else now
        user.token_valid_until = base + timedelta(days=plan_days)

        order.status = "paid"
        order.transaction_id = transaction_id
        order.paid_at = now

        db.session.add(user)
        db.session.add(order)
        db.session.commit()
        return _wechat_notify_ok()
    except Exception as exc:
        db.session.rollback()
        logger.exception("wechat notify error: %s", exc)
        return _wechat_notify_fail("服务端处理失败")


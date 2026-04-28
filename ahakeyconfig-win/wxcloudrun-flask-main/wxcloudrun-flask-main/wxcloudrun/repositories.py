"""
仓储层模块。

职责：
1. 封装通用数据访问查询。
2. 为服务层提供稳定、可复用的数据访问接口。
"""

from typing import Optional

from wxcloudrun.models import PaymentOrder, QuotaPolicy, User


def get_user_by_id(user_id: int) -> Optional[User]:
    """按用户 ID 查询用户。"""
    return User.query.filter(User.id == user_id).first()


def get_user_by_phone(phone: str) -> Optional[User]:
    """按手机号查询用户。"""
    return User.query.filter(User.phone == phone).first()


def get_order_by_trade_no(out_trade_no: str) -> Optional[PaymentOrder]:
    """按商户订单号查询支付订单。"""
    return PaymentOrder.query.filter(PaymentOrder.out_trade_no == out_trade_no).first()


def get_quota_policy(policy_id: int = 1) -> Optional[QuotaPolicy]:
    """查询全局配额策略（默认主键为 1）。"""
    return QuotaPolicy.query.get(policy_id)


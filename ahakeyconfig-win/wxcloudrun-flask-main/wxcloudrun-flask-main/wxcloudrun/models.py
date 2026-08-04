"""
数据模型模块。

职责：
1. 定义用户、配额策略、支付订单、兑换码等核心业务表。
2. 作为服务层和仓储层统一依赖的数据结构。
"""

from datetime import datetime

from sqlalchemy.sql import func

from wxcloudrun.extensions import db


class User(db.Model):
    """终端用户账号表。"""

    __tablename__ = "vibe_users"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    phone = db.Column(db.String(32), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    created_at = db.Column(
        db.TIMESTAMP,
        nullable=False,
        server_default=func.current_timestamp(),
        default=datetime.utcnow,
    )
    token_valid_until = db.Column(db.DateTime, nullable=True)

    limit_daily = db.Column(db.Integer, nullable=False, default=0)
    limit_weekly = db.Column(db.Integer, nullable=False, default=0)
    limit_monthly = db.Column(db.Integer, nullable=False, default=0)

    used_daily = db.Column(db.Integer, nullable=False, default=0)
    used_weekly = db.Column(db.Integer, nullable=False, default=0)
    used_monthly = db.Column(db.Integer, nullable=False, default=0)

    daily_period_key = db.Column(db.String(16), nullable=False, default="")
    weekly_period_key = db.Column(db.String(16), nullable=False, default="")
    monthly_period_key = db.Column(db.String(16), nullable=False, default="")


class QuotaPolicy(db.Model):
    """全局配额策略表。"""

    __tablename__ = "vibe_quota_policy"

    id = db.Column(db.Integer, primary_key=True)
    enable_daily = db.Column(db.Boolean, nullable=False, default=True)
    enable_weekly = db.Column(db.Boolean, nullable=False, default=True)
    enable_monthly = db.Column(db.Boolean, nullable=False, default=True)
    default_limit_daily = db.Column(db.Integer, nullable=False, default=100_000)
    default_limit_weekly = db.Column(db.Integer, nullable=False, default=500_000)
    default_limit_monthly = db.Column(db.Integer, nullable=False, default=2_000_000)
    recharge_monthly_fen = db.Column(db.Integer, nullable=False, default=100)
    recharge_quarterly_fen = db.Column(db.Integer, nullable=False, default=270)
    recharge_yearly_fen = db.Column(db.Integer, nullable=False, default=999)


class PaymentOrder(db.Model):
    """支付订单表（用于回调幂等与权益生效）。"""

    __tablename__ = "vibe_payment_orders"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    out_trade_no = db.Column(db.String(64), unique=True, nullable=False, index=True)
    user_id = db.Column(db.Integer, nullable=False, index=True)
    plan = db.Column(db.String(16), nullable=False)
    amount_fen = db.Column(db.Integer, nullable=False)
    status = db.Column(db.String(16), nullable=False, default="pending")
    transaction_id = db.Column(db.String(64), nullable=True, default="")
    paid_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(
        db.TIMESTAMP,
        nullable=False,
        server_default=func.current_timestamp(),
        default=datetime.utcnow,
    )


class CouponCode(db.Model):
    """兑换码表（仅存哈希，不存明文）。"""

    __tablename__ = "vibe_coupon_codes"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    code_hash = db.Column(db.String(64), unique=True, nullable=False, index=True)
    benefit_days = db.Column(db.Integer, nullable=False, default=60)
    expires_at = db.Column(db.DateTime, nullable=True)
    used_by_user_id = db.Column(db.Integer, nullable=True, index=True)
    used_at = db.Column(db.DateTime, nullable=True)
    disabled = db.Column(db.Boolean, nullable=False, default=False)
    created_by_admin_phone = db.Column(db.String(32), nullable=True, default="")
    batch_id = db.Column(db.String(64), nullable=False, default="", index=True)
    created_at = db.Column(
        db.TIMESTAMP,
        nullable=False,
        server_default=func.current_timestamp(),
        default=datetime.utcnow,
    )


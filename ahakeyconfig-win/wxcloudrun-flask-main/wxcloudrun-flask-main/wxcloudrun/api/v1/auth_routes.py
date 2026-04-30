"""
API v1 - 认证域路由。

包含：
1. 用户注册。
2. 用户登录。
3. 当前用户信息查询。
"""

from sqlalchemy.exc import SQLAlchemyError
from flask import request

import config
from wxcloudrun.models import User
from wxcloudrun.response import make_err_response, make_succ_response
from wxcloudrun.services.auth_service import (
    create_access_token,
    hash_password,
    verify_password,
)
from wxcloudrun.api.v1.shared import (
    PHONE_RE,
    bp,
    db,
    db_err_detail,
    get_or_create_policy,
    logger,
    require_user,
    user_me_payload,
)


@bp.route("/auth/register", methods=["POST"])
def register():
    """注册新用户并签发访问令牌。"""
    data = request.get_json(silent=True) or {}
    phone = (data.get("phone") or "").strip()
    password = data.get("password") or ""
    if not PHONE_RE.match(phone):
        return make_err_response("手机号格式应为 11 位且以 1 开头")
    if len(password) < 8:
        return make_err_response("密码至少 8 位")

    try:
        if User.query.filter_by(phone=phone).first():
            return make_err_response("该手机号已注册")
        policy = get_or_create_policy()
        user = User(
            phone=phone,
            password_hash=hash_password(password),
            limit_daily=policy.default_limit_daily,
            limit_weekly=policy.default_limit_weekly,
            limit_monthly=policy.default_limit_monthly,
        )
        db.session.add(user)
        db.session.commit()
    except SQLAlchemyError as exc:
        db.session.rollback()
        logger.exception("register db error")
        return make_err_response(
            "数据库错误：请确认 MySQL 已启动、已创建库 vibe_keyboard，且环境变量 "
            "MYSQL_USERNAME / MYSQL_PASSWORD / MYSQL_ADDRESS 正确；然后重启本服务。"
            " 技术详情: {}".format(db_err_detail(exc))
        )

    token = create_access_token(user)
    return make_succ_response(
        {
            "access_token": token,
            "token_type": "Bearer",
            "expires_in": config.JWT_EXPIRES_SECONDS,
        }
    )


@bp.route("/auth/login", methods=["POST"])
def login():
    """用户登录并签发访问令牌。"""
    data = request.get_json(silent=True) or {}
    phone = (data.get("phone") or "").strip()
    password = data.get("password") or ""
    try:
        user = User.query.filter_by(phone=phone).first()
    except SQLAlchemyError as exc:
        logger.exception("login db error")
        return make_err_response(
            "数据库错误：请检查 MySQL 与 MYSQL_* 环境变量后重启服务。详情: {}".format(
                db_err_detail(exc)
            )
        )
    if not user or not verify_password(password, user.password_hash):
        return make_err_response("手机号或密码错误")

    token = create_access_token(user)
    return make_succ_response(
        {
            "access_token": token,
            "token_type": "Bearer",
            "expires_in": config.JWT_EXPIRES_SECONDS,
        }
    )


@bp.route("/users/me", methods=["GET"])
def users_me():
    """返回当前登录用户的账号和配额信息。"""
    result = require_user()
    if isinstance(result, tuple):
        return result[0], result[1]
    user = result
    policy = get_or_create_policy()
    return make_succ_response(user_me_payload(user, policy))


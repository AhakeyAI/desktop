"""
鉴权服务模块。

职责：
1. 处理密码哈希与校验。
2. 创建和解析 JWT 访问令牌。
3. 判断用户是否为管理员账号。
"""

from datetime import datetime, timedelta

import bcrypt
import jwt

import config
from wxcloudrun.models import User


def hash_password(plain: str) -> str:
    """对明文密码执行 bcrypt 哈希。"""
    return bcrypt.hashpw(plain.encode("utf-8"), bcrypt.gensalt()).decode("ascii")


def verify_password(plain: str, password_hash: str) -> bool:
    """校验明文密码与哈希值是否匹配。"""
    try:
        return bcrypt.checkpw(plain.encode("utf-8"), password_hash.encode("ascii"))
    except (ValueError, TypeError):
        return False


def is_admin_phone(phone: str) -> bool:
    """根据管理员手机号白名单判断是否管理员。"""
    if not phone or not config.ADMIN_PHONES:
        return False
    return phone in config.ADMIN_PHONES


def create_access_token(user: User) -> str:
    """为用户创建访问令牌。"""
    payload = {
        "sub": str(user.id),
        "phone": user.phone,
        "adm": is_admin_phone(user.phone),
        "exp": datetime.utcnow() + timedelta(seconds=config.JWT_EXPIRES_SECONDS),
    }
    tok = jwt.encode(payload, config.JWT_SECRET, algorithm="HS256")
    if isinstance(tok, bytes):
        return tok.decode("ascii")
    return tok


def decode_access_token(token: str):
    """解析并验证访问令牌，失败时返回 None。"""
    try:
        return jwt.decode(token, config.JWT_SECRET, algorithms=["HS256"])
    except jwt.PyJWTError:
        return None

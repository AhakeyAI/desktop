"""
项目配置模块。

职责：
1. 从环境变量读取服务运行配置。
2. 提供统一的模块级配置常量，供 Flask 应用、鉴权、支付、推理模块使用。

说明：
- 默认优先加载项目根目录下 `.env` 文件。
- 所有字符串和注释均采用 UTF-8。
"""

import os
from pathlib import Path

# 先加载 .env，避免本地 PowerShell 环境变量污染导致配置不一致。
_env_dir = Path(__file__).resolve().parent
try:
    from dotenv import load_dotenv

    load_dotenv(_env_dir / ".env", override=True)
except ImportError:
    pass

# ==============================
# Flask 运行配置
# ==============================
# 是否启用 Flask Debug 模式。
# 可选值示例：1/0、true/false、yes/no。
DEBUG = os.environ.get("FLASK_DEBUG", "1").strip().lower() not in ("0", "false", "no")

# ==============================
# MySQL 配置
# ==============================
# MySQL 用户名。
MYSQL_USERNAME = os.environ.get("MYSQL_USERNAME", "root")
# MySQL 密码。
MYSQL_PASSWORD = os.environ.get("MYSQL_PASSWORD", "root")
# MySQL 地址，格式：host:port。
MYSQL_ADDRESS = os.environ.get("MYSQL_ADDRESS", "127.0.0.1:3306")
# MySQL 库名（已规范默认值为 vibe_keyboard）。
MYSQL_DATABASE = os.environ.get("MYSQL_DATABASE", "vibe_keyboard")

# ==============================
# JWT 配置
# ==============================
# JWT 签名密钥，生产环境务必替换。
JWT_SECRET = os.environ.get("JWT_SECRET", "change-me-in-production")
# JWT 过期时间（秒），默认 7 天。
JWT_EXPIRES_SECONDS = int(os.environ.get("JWT_EXPIRES_SECONDS", str(7 * 24 * 3600)))

# ==============================
# 管理员配置
# ==============================
# 管理员手机号列表，逗号分隔。
# 示例：13800138000,13900139000
ADMIN_PHONES = [p.strip() for p in os.environ.get("ADMIN_PHONES", "").split(",") if p.strip()]

# ==============================
# 兑换码配置
# ==============================
# 兑换码哈希加盐（服务端私有配置）。
COUPON_CODE_PEPPER = os.environ.get("COUPON_CODE_PEPPER", "change-me-coupon-pepper")
# 免费兑换默认天数。
FREE_COUPON_DAYS = int(os.environ.get("FREE_COUPON_DAYS", "60"))
# 兑换防刷时间窗（分钟）。
COUPON_REDEEM_WINDOW_MINUTES = int(os.environ.get("COUPON_REDEEM_WINDOW_MINUTES", "10"))
# 时间窗内允许的最大失败次数。
COUPON_REDEEM_MAX_FAILS = int(os.environ.get("COUPON_REDEEM_MAX_FAILS", "5"))
# 超过失败次数后的锁定时长（分钟）。
COUPON_REDEEM_LOCKOUT_MINUTES = int(os.environ.get("COUPON_REDEEM_LOCKOUT_MINUTES", "15"))

# ==============================
# 火山方舟推理配置
# ==============================
# 方舟 API Key。
ARK_API_KEY = os.environ.get("ARK_API_KEY", "")
# 方舟 API Base URL。
ARK_BASE_URL = os.environ.get("ARK_BASE_URL", "https://ark.cn-beijing.volces.com/api/v3")
# 方舟模型 ID（推理接入点 ID）。
ARK_MODEL_ID = os.environ.get("ARK_MODEL_ID", "")

# ==============================
# 客户端发布/更新配置
# ==============================
# 键盘配置工具最新版本号；留空表示不向客户端提示更新。
CONFIG_TOOL_LATEST_VERSION = os.environ.get("CONFIG_TOOL_LATEST_VERSION", "").strip()
# 键盘配置工具安装包下载地址；建议填写微信云托管静态资源或对象存储 HTTPS 地址。
CONFIG_TOOL_DOWNLOAD_URL = os.environ.get("CONFIG_TOOL_DOWNLOAD_URL", "").strip()
# 键盘配置工具更新说明；可直接填多行文本。
CONFIG_TOOL_RELEASE_NOTES = os.environ.get("CONFIG_TOOL_RELEASE_NOTES", "").strip()

# ==============================
# 兼容别名（旧代码仍可运行）
# ==============================
username = MYSQL_USERNAME
password = MYSQL_PASSWORD
db_address = MYSQL_ADDRESS
mysql_database = MYSQL_DATABASE

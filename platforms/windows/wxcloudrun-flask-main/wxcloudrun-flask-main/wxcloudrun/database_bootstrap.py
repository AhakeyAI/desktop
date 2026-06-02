"""
数据库引导与兼容迁移模块。

职责：
1. 解析数据库地址并构造 SQLAlchemy URI。
2. 在需要时自动创建数据库。
3. 补齐业务必需字段。
4. 清理历史模板和无意义遗留字段。
"""

import logging
import os
import re
from urllib.parse import quote_plus

import pymysql

import config

_log = logging.getLogger("wxcloudrun.database_bootstrap")


def parse_mysql_host_port(address: str):
    """
    解析 MYSQL_ADDRESS，返回 (host, port)。

    支持格式：
    - host:port
    - [ipv6]:port
    - host（无端口时默认 3306）
    """
    address = (address or "").strip()
    if not address:
        return "127.0.0.1", 3306
    if address.startswith("["):
        m = re.match(r"^\[([^\]]+)\](?::(\d+))?$", address)
        if m:
            return m.group(1), int(m.group(2) or 3306)
    if ":" in address:
        host, _, port_s = address.rpartition(":")
        if port_s.isdigit():
            return host, int(port_s)
    return address, 3306


def build_sqlalchemy_uri() -> str:
    """
    构建 SQLAlchemy 数据库连接 URI。

    注意：
    - 用户名和密码会进行 URL 编码，避免特殊字符导致连接失败。
    """
    return "mysql://{}:{}@{}/{}".format(
        quote_plus(config.MYSQL_USERNAME),
        quote_plus(config.MYSQL_PASSWORD),
        config.MYSQL_ADDRESS,
        config.MYSQL_DATABASE,
    )


def ensure_mysql_database_exists():
    """
    根据配置确保数据库存在。

    可通过 MYSQL_AUTO_CREATE_DATABASE=0 禁用自动建库。
    """
    if os.environ.get("MYSQL_AUTO_CREATE_DATABASE", "1").strip().lower() in ("0", "false", "no"):
        return
    dbname = (config.MYSQL_DATABASE or "").strip()
    if not dbname or not re.match(r"^[A-Za-z0-9_]+$", dbname):
        _log.warning("MYSQL_DATABASE 配置为空或格式非法，跳过自动建库。")
        return
    host, port = parse_mysql_host_port(config.MYSQL_ADDRESS)
    conn = pymysql.connect(
        host=host,
        port=port,
        user=config.MYSQL_USERNAME,
        password=config.MYSQL_PASSWORD,
        charset="utf8mb4",
    )
    try:
        with conn.cursor() as cur:
            cur.execute(
                "CREATE DATABASE IF NOT EXISTS `{}` "
                "CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci".format(dbname)
            )
        conn.commit()
    finally:
        conn.close()


def _column_exists(cur, dbname: str, table: str, col: str) -> bool:
    """判断指定表字段是否存在。"""
    cur.execute(
        "SELECT 1 FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA=%s AND TABLE_NAME=%s AND COLUMN_NAME=%s LIMIT 1",
        (dbname, table, col),
    )
    return bool(cur.fetchone())


def ensure_business_columns():
    """
    补齐业务必需字段。

    适用于老库升级到新版本时的兼容处理。
    """
    host, port = parse_mysql_host_port(config.MYSQL_ADDRESS)
    dbname = (config.MYSQL_DATABASE or "").strip()
    if not dbname:
        return
    conn = pymysql.connect(
        host=host,
        port=port,
        user=config.MYSQL_USERNAME,
        password=config.MYSQL_PASSWORD,
        database=dbname,
        charset="utf8mb4",
    )
    try:
        with conn.cursor() as cur:
            quota_cols = {
                "recharge_monthly_fen": "INT NOT NULL DEFAULT 100",
                "recharge_quarterly_fen": "INT NOT NULL DEFAULT 270",
                "recharge_yearly_fen": "INT NOT NULL DEFAULT 999",
            }
            for col, ddl in quota_cols.items():
                if not _column_exists(cur, dbname, "vibe_quota_policy", col):
                    cur.execute("ALTER TABLE `vibe_quota_policy` ADD COLUMN `{}` {}".format(col, ddl))

            if not _column_exists(cur, dbname, "vibe_users", "token_valid_until"):
                cur.execute("ALTER TABLE `vibe_users` ADD COLUMN `token_valid_until` DATETIME NULL")
        conn.commit()
    finally:
        conn.close()


def cleanup_legacy_schema():
    """
    清理历史模板和无意义遗留结构。

    当前清理项：
    - 删除模板计数器表 Counters
    - 删除用户表历史字段 token_balance
    - 删除策略表历史字段 default_token_balance
    """
    host, port = parse_mysql_host_port(config.MYSQL_ADDRESS)
    dbname = (config.MYSQL_DATABASE or "").strip()
    if not dbname:
        return
    conn = pymysql.connect(
        host=host,
        port=port,
        user=config.MYSQL_USERNAME,
        password=config.MYSQL_PASSWORD,
        database=dbname,
        charset="utf8mb4",
    )
    try:
        with conn.cursor() as cur:
            cur.execute("DROP TABLE IF EXISTS `Counters`")

            if _column_exists(cur, dbname, "vibe_users", "token_balance"):
                cur.execute("ALTER TABLE `vibe_users` DROP COLUMN `token_balance`")

            if _column_exists(cur, dbname, "vibe_quota_policy", "default_token_balance"):
                cur.execute("ALTER TABLE `vibe_quota_policy` DROP COLUMN `default_token_balance`")
        conn.commit()
    finally:
        conn.close()

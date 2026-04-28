"""
应用初始化模块（应用工厂）。

职责：
1. 创建 Flask 应用实例并注入配置。
2. 初始化数据库扩展、加载模型、注册业务路由。
3. 在启动阶段执行数据库引导与历史结构清理。
"""

import logging

import pymysql
from flask import Flask, jsonify

import config
from wxcloudrun.database_bootstrap import (
    build_sqlalchemy_uri,
    cleanup_legacy_schema,
    ensure_business_columns,
    ensure_mysql_database_exists,
)
from wxcloudrun.extensions import db
from wxcloudrun.route_registry import register_blueprints

# 兼容 SQLAlchemy 使用 MySQLdb 驱动名的连接方式。
pymysql.install_as_MySQLdb()

_log = logging.getLogger("wxcloudrun")


def create_app() -> Flask:
    """创建并配置 Flask 应用实例。"""
    app = Flask(__name__, instance_relative_config=True)
    app.config["DEBUG"] = config.DEBUG
    app.config["SQLALCHEMY_DATABASE_URI"] = build_sqlalchemy_uri()
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config.from_object("config")

    # 初始化数据库扩展。
    db.init_app(app)

    # 导入模型，确保 create_all 可获取全部元数据。
    import wxcloudrun.models  # noqa: F401

    # 注册业务路由。
    register_blueprints(app)

    @app.route("/healthz", methods=["GET"])
    def healthz():
        """服务健康检查接口。"""
        return jsonify({"status": "ok"})

    @app.before_request
    def _lazy_schema_ensure():
        """请求前兜底补齐业务字段，兼容数据库启动慢或旧库升级场景。"""
        try:
            ensure_business_columns()
        except Exception:
            # 兜底逻辑不应阻断业务请求。
            pass

    try:
        with app.app_context():
            # 启动阶段数据库引导。
            ensure_mysql_database_exists()
            db.create_all()
            ensure_business_columns()
            cleanup_legacy_schema()

            from wxcloudrun.services.quota_service import get_or_create_policy

            get_or_create_policy()
    except Exception as exc:
        _log.warning("Database init failed (retry on requests): %s", exc, exc_info=True)

    return app


# 默认导出应用对象，保持 run.py 导入方式兼容。
app = create_app()
# 导出 db，保持现有模块 `from wxcloudrun import db` 兼容。
__all__ = ["app", "db", "create_app"]

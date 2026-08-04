"""
路由注册模块。

职责：
1. 统一聚合并注册业务蓝图。
2. 作为应用工厂与 API 子模块之间的桥接层。
"""

from flask import Flask

from wxcloudrun.api.v1 import bp as api_v1_bp


def register_blueprints(app: Flask) -> None:
    """向应用注册所有业务蓝图。"""
    app.register_blueprint(api_v1_bp)


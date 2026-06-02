"""
API v1 路由聚合入口。

职责：
1. 聚合并触发各业务域子路由注册。
2. 对外统一导出 v1 Blueprint。
"""

from wxcloudrun.api.v1.shared import bp

# 导入子路由模块以触发路由注册。
from wxcloudrun.api.v1 import admin_routes as _admin_routes  # noqa: F401
from wxcloudrun.api.v1 import auth_routes as _auth_routes  # noqa: F401
from wxcloudrun.api.v1 import client_routes as _client_routes  # noqa: F401
from wxcloudrun.api.v1 import coupon_routes as _coupon_routes  # noqa: F401
from wxcloudrun.api.v1 import inference_routes as _inference_routes  # noqa: F401
from wxcloudrun.api.v1 import payment_routes as _payment_routes  # noqa: F401

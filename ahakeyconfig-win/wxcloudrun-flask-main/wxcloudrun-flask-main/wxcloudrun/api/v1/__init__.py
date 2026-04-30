"""
API v1 包初始化模块。

作用：
1. 声明这是一个 Python 包，允许 `wxcloudrun.api.v1.*` 方式导入。
2. 对外统一暴露 `bp`（Blueprint），供上层路由注册器使用。
3. 将“路由聚合逻辑”与“包入口”分离，减少耦合。
"""

from wxcloudrun.api.v1.routes import bp  # noqa: F401


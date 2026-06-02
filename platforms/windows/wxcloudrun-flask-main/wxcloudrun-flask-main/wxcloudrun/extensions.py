"""
数据库扩展模块。

职责：
1. 统一创建并导出 SQLAlchemy 扩展实例。
2. 供应用初始化、模型层、DAO 层共享同一个数据库对象。
"""

from flask_sqlalchemy import SQLAlchemy

# 全局数据库扩展实例。
db = SQLAlchemy()


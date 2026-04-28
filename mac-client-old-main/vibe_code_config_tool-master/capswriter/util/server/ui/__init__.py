# coding: utf-8
"""
服务端 UI 门面模块 (macOS 适配版)

macOS 版本不使用独立托盘图标，所有 UI 功能集成到 PySide6 GUI。
此模块提供空的占位函数，防止导入错误。
"""

from .. import logger


def enable_min_to_tray(*args, **kwargs):
    """macOS: 不使用托盘，空实现"""
    pass


def stop_tray(*args, **kwargs):
    """macOS: 不使用托盘，空实现"""
    pass


def toast(*args, **kwargs):
    """macOS: toast 通知不可用"""
    pass


__all__ = [
    'logger',
    'enable_min_to_tray',
    'stop_tray',
    'toast',
]

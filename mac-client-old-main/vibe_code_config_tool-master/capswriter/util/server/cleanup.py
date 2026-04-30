# coding: utf-8
"""
服务端资源清理与辅助模块 (macOS 适配版)

负责服务端资源清理和Banner显示。
macOS 不使用独立托盘图标（集成到 PySide6 GUI）。
"""

import os
import asyncio
from rich.console import Console

from config_server import ServerConfig as Config, __version__
from . import logger
from util.common.lifecycle import lifecycle
from util.server.state import get_state

console = Console(highlight=False)

# 计算项目根目录: util/server/cleanup.py -> util/server -> util -> root
BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def request_exit_from_tray(icon=None, item=None):
    """托盘退出请求回调（macOS 下不使用）"""
    logger.info("托盘退出: 用户点击退出菜单")
    lifecycle.request_shutdown(reason="Tray Icon")


def cleanup_server_resources():
    """
    清理服务端资源
    """
    state = get_state()

    logger.info("=" * 50)
    logger.info("开始清理服务端资源...")

    # 终止识别子进程
    _recognize_process = state.recognize_process
    if _recognize_process and _recognize_process.is_alive():
        logger.info("正在终止识别子进程...")
        _recognize_process.terminate()
        _recognize_process.join(timeout=5)
        if _recognize_process.is_alive():
            logger.warning("识别进程未能在5秒内退出，强制终止")
            try:
                _recognize_process.kill()
                _recognize_process.join(timeout=1)
            except Exception as e:
                logger.error(f"强制终止失败: {e}")
        else:
            logger.info("识别进程已正常退出")
    elif _recognize_process:
        logger.info("识别进程已退出")

    logger.info("服务端资源清理完成")
    console.print('[green4]再见！')


def setup_tray():
    """macOS: 托盘功能已禁用，跳过"""
    pass


def print_banner():
    """打印启动信息"""
    console.line(2)
    console.rule('[bold #d55252]CapsWriter Offline Server'); console.line()
    console.print(f'版本：[bold green]{__version__}', end='\n\n')
    console.print(f'项目地址：[cyan underline]https://github.com/HaujetZhao/CapsWriter-Offline', end='\n\n')
    console.print(f'当前基文件夹：[cyan underline]{BASE_DIR}', end='\n\n')
    console.print(f'绑定的服务地址：[cyan underline]{Config.addr}:{Config.port}', end='\n\n')

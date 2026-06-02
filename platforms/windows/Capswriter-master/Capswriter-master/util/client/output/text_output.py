# coding: utf-8
"""
文本输出模块

将识别结果输出到当前窗口；云 Typeless 在 result_processor 中通过根目录 text_optimizer.optimize_text 完成。
"""

from __future__ import annotations

import asyncio
import platform
import subprocess
from typing import Optional
import re
import pyclip

from config_client import ClientConfig as Config
from . import logger

os_name_global = platform.system()
if os_name_global != "Linux":
    import keyboard


class TextOutput:
    """
    文本输出器

    提供文本输出功能，强制使用粘贴方式并统一底层库以规避输入法冲突。
    """

    @staticmethod
    def strip_punc(text: str) -> str:
        """
        消除末尾最后一个标点
        """
        if not text or not Config.trash_punc:
            return text
        clean_text = re.sub(f"(?<=.)[{Config.trash_punc}]$", "", text)
        return clean_text

    async def output(self, text: str, paste: Optional[bool] = None) -> None:
        """
        输出文本（上游已完成 ASR、热词与可选的云 Typeless，此处只做粘贴）。
        """
        if not text:
            return

        paste_mode = True

        if paste_mode:
            await self._paste_text(text)
        else:
            self._type_text(text)

    async def _paste_text(self, text: str) -> None:
        """
        通过粘贴方式输出文本 (安全输出模式)
        """
        logger.debug(f"使用粘贴方式输出文本，长度: {len(text)}")

        try:
            temp = pyclip.paste().decode("utf-8")
        except Exception:
            temp = ""

        pyclip.copy(text)

        await asyncio.sleep(0.05)

        os_name = platform.system()

        if os_name == "Darwin":
            keyboard.send("command+v")
        elif os_name == "Windows":
            keyboard.send("ctrl+v")
        elif os_name == "Linux":
            try:
                subprocess.run(["xdotool", "key", "ctrl+v"], check=True)
            except Exception as e:
                logger.error(f"Linux 粘贴失败，请确保已安装 xdotool: {e}")

        logger.debug("已发送粘贴命令")

        if getattr(Config, "restore_clip", False):
            await asyncio.sleep(0.15)
            pyclip.copy(temp)
            logger.debug("剪贴板已恢复")

    def _type_text(self, text: str) -> None:
        """
        通过模拟打字方式输出文本 (已废弃/仅作备用)
        """
        logger.debug(f"使用打字方式输出文本，长度: {len(text)}")
        if platform.system() != "Linux":
            keyboard.write(text)
        else:
            logger.warning("Linux 环境下已禁用 keyboard.write，请确保使用粘贴模式")

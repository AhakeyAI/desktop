# coding: utf-8
from __future__ import annotations

import os
import sys
import threading
import time
from typing import TYPE_CHECKING, Optional

import numpy as np
import sounddevice as sd

from util.common.lifecycle import lifecycle
from util.client.state import console

from . import logger

if TYPE_CHECKING:
    from util.client.state import ClientState


INPUT_DEVICE_HINT_ENV = "CAPSWRITER_INPUT_DEVICE_HINT"
VIRTUAL_INPUT_PATTERNS = (
    "todesk",
    "virtual audio",
    "vb-audio",
    "cable output",
    "cable-a",
    "stereo mix",
)


def _is_virtual_input_device(name: str) -> bool:
    normalized = name.lower()
    return any(pattern in normalized for pattern in VIRTUAL_INPUT_PATTERNS)


class AudioStreamManager:
    SAMPLE_RATE = 48000
    BLOCK_DURATION = 0.05

    def __init__(self, state: "ClientState"):
        self.state = state
        self._channels = 1
        self._running = False

    @staticmethod
    def _default_input_device_index() -> Optional[int]:
        try:
            default_devices = sd.default.device
        except Exception:
            return None

        if isinstance(default_devices, (list, tuple)) and default_devices:
            try:
                idx = int(default_devices[0])
            except (TypeError, ValueError):
                return None
            return idx if idx >= 0 else None

        try:
            idx = int(default_devices)
        except (TypeError, ValueError):
            return None
        return idx if idx >= 0 else None

    @staticmethod
    def _list_input_devices() -> list[tuple[int, dict]]:
        devices: list[tuple[int, dict]] = []
        for index, device in enumerate(sd.query_devices()):
            if device.get("max_input_channels", 0) > 0:
                devices.append((index, device))
        return devices

    def _resolve_input_device(self) -> tuple[Optional[int], dict, Optional[str]]:
        hint = os.environ.get(INPUT_DEVICE_HINT_ENV, "").strip().lower()
        input_devices = self._list_input_devices()

        if hint:
            for candidate_index, candidate in input_devices:
                candidate_name = str(candidate.get("name", ""))
                if hint == str(candidate_index) or hint in candidate_name.lower():
                    return (
                        candidate_index,
                        candidate,
                        f"根据环境变量 {INPUT_DEVICE_HINT_ENV} 使用输入设备 {candidate_name}",
                    )

        selected_index = self._default_input_device_index()
        selected_device = None

        if selected_index is not None:
            selected_device = sd.query_devices(selected_index)
        else:
            selected_device = sd.query_devices(kind="input")

        selected_name = str(selected_device.get("name", "未知设备"))
        fallback_reason = None

        if _is_virtual_input_device(selected_name):
            for candidate_index, candidate in input_devices:
                candidate_name = str(candidate.get("name", ""))
                if candidate_index == selected_index:
                    continue
                if _is_virtual_input_device(candidate_name):
                    continue
                selected_index = candidate_index
                selected_device = candidate
                fallback_reason = (
                    f"默认输入设备 {selected_name} 看起来是虚拟设备，自动切换到 {candidate_name}"
                )
                break

        return selected_index, selected_device, fallback_reason

    def _audio_callback(
        self,
        indata: np.ndarray,
        frames: int,
        time_info,
        status: sd.CallbackFlags,
    ) -> None:
        if not self.state.recording:
            return

        import asyncio

        if self.state.loop and self.state.queue_in:
            asyncio.run_coroutine_threadsafe(
                self.state.queue_in.put(
                    {
                        "type": "data",
                        "time": time.time(),
                        "data": indata.copy(),
                    }
                ),
                self.state.loop,
            )

    def _on_stream_finished(self) -> None:
        if not threading.main_thread().is_alive():
            return

        if self._running and not lifecycle.is_shutting_down:
            logger.info("音频流意外结束，正在尝试重启...")
            self.reopen()
        else:
            logger.debug("音频流已正常结束")

    def open(self) -> Optional[sd.InputStream]:
        try:
            device_index, device, fallback_reason = self._resolve_input_device()
            self._channels = max(1, min(2, int(device.get("max_input_channels", 1) or 1)))
            device_name = str(device.get("name", "未知设备"))

            if fallback_reason:
                logger.warning(fallback_reason)
                console.print(f"[yellow]{fallback_reason}[/yellow]", end="\n\n")

            console.print(
                f"使用音频输入设备：[italic]{device_name}[/italic]，声道数：{self._channels}",
                end="\n\n",
            )
            logger.info(f"找到音频输入设备: {device_name}, 声道数: {self._channels}")
        except UnicodeDecodeError:
            console.print(
                "由于编码问题，暂时无法获取麦克风设备名",
                end="\n\n",
                style="bright_red",
            )
            logger.warning("无法获取音频输入设备名（编码问题）")
            return None
        except sd.PortAudioError:
            console.print("没有找到麦克风设备", end="\n\n", style="bright_red")
            logger.error("未找到麦克风设备")
            input("按回车键退出")
            sys.exit(1)

        try:
            stream = sd.InputStream(
                samplerate=self.SAMPLE_RATE,
                blocksize=int(self.BLOCK_DURATION * self.SAMPLE_RATE),
                device=device_index,
                dtype="float32",
                channels=self._channels,
                callback=self._audio_callback,
                finished_callback=self._on_stream_finished,
            )
            stream.start()

            self.state.stream = stream
            self._running = True
            logger.debug(
                "音频流已启动: 采样率=%s, blocksize=%s",
                self.SAMPLE_RATE,
                int(self.BLOCK_DURATION * self.SAMPLE_RATE),
            )
            return stream
        except Exception as exc:
            logger.error(f"创建音频流失败: {exc}", exc_info=True)
            return None

    def close(self) -> None:
        self._running = False
        if self.state.stream is not None:
            try:
                self.state.stream.close()
                logger.debug("音频流已关闭")
            except Exception as exc:
                logger.debug(f"关闭音频流时发生错误: {exc}")
            finally:
                self.state.stream = None

    def reopen(self) -> Optional[sd.InputStream]:
        logger.info("正在重启音频流...")
        self.close()

        try:
            sd._terminate()
            sd._ffi.dlclose(sd._lib)
            sd._lib = sd._ffi.dlopen(sd._libname)
            sd._initialize()
        except Exception as exc:
            logger.warning(f"重载 PortAudio 时发生警告: {exc}")

        time.sleep(0.1)
        return self.open()

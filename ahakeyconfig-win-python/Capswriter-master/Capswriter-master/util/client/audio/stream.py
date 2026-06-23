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


def _console_safe_text(text: str) -> str:
    """Make text printable on legacy GBK Windows consoles."""
    if sys.platform != "win32":
        return text
    encoding = getattr(sys.stdout, "encoding", None) or "gbk"
    try:
        text.encode(encoding)
        return text
    except UnicodeEncodeError:
        return text.encode(encoding, errors="replace").decode(encoding, errors="replace")


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
                        f"Using input device from {INPUT_DEVICE_HINT_ENV}: {candidate_name}",
                    )

        selected_index = self._default_input_device_index()
        if selected_index is not None:
            selected_device = sd.query_devices(selected_index)
        else:
            selected_device = sd.query_devices(kind="input")

        selected_name = str(selected_device.get("name", "Unknown input device"))
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
                    f'Default input device "{selected_name}" looks virtual; switched to "{candidate_name}".'
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
            logger.info("Audio stream stopped unexpectedly; trying to reopen.")
            self.reopen()
        else:
            logger.debug("Audio stream closed normally.")

    def open(self) -> Optional[sd.InputStream]:
        try:
            device_index, device, fallback_reason = self._resolve_input_device()
            self._channels = max(1, min(2, int(device.get("max_input_channels", 1) or 1)))
            device_name = str(device.get("name", "Unknown input device"))

            if fallback_reason:
                logger.warning(fallback_reason)
                console.print(f"[yellow]{_console_safe_text(fallback_reason)}[/yellow]", end="\n\n")

            console.print(
                f"Input device: [italic]{_console_safe_text(device_name)}[/italic], channels: {self._channels}",
                end="\n\n",
            )
            logger.info("Found audio input device: %s, channels=%s", device_name, self._channels)
        except (UnicodeDecodeError, UnicodeEncodeError):
            console.print(
                "Unable to render the microphone device name because of console encoding.",
                end="\n\n",
                style="bright_red",
            )
            logger.warning("Unable to render audio input device name because of encoding issues.")
            return None
        except sd.PortAudioError:
            console.print("No microphone device was found.", end="\n\n", style="bright_red")
            logger.error("No microphone device found")
            input("Press Enter to exit.")
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
                "Audio stream started: samplerate=%s, blocksize=%s",
                self.SAMPLE_RATE,
                int(self.BLOCK_DURATION * self.SAMPLE_RATE),
            )
            return stream
        except Exception as exc:
            logger.error("Failed to create audio stream: %s", exc, exc_info=True)
            return None

    def close(self) -> None:
        self._running = False
        if self.state.stream is not None:
            try:
                self.state.stream.close()
                logger.debug("Audio stream closed.")
            except Exception as exc:
                logger.debug("Error while closing audio stream: %s", exc)
            finally:
                self.state.stream = None

    def reopen(self) -> Optional[sd.InputStream]:
        logger.info("Reopening audio stream...")
        self.close()

        try:
            sd._terminate()
            sd._ffi.dlclose(sd._lib)
            sd._lib = sd._ffi.dlopen(sd._libname)
            sd._initialize()
        except Exception as exc:
            logger.warning("Reloading PortAudio raised a warning: %s", exc)

        time.sleep(0.1)
        return self.open()

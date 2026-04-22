# coding: utf-8
"""轻量语音悬浮窗。"""

from __future__ import annotations

import queue
import threading
import tkinter as tk
from dataclasses import dataclass
from typing import Optional

from . import logger

_HUD_BG = "#14181E"
_HUD_BORDER = "#2C3440"
_STATUS_COLORS = {
    "recording": "#E74C3C",
    "processing": "#F5A623",
    "ready": "#2ECC71",
    "error": "#E74C3C",
}
_STATUS_TEXT = {
    "recording": "语音输入中",
    "processing": "处理中",
    "ready": "语音已就绪",
    "error": "语音异常",
}


@dataclass
class _HudCommand:
    action: str
    status: str = ""
    text: str = ""


class VoiceHud:
    """独立运行的轻量悬浮窗控制器。"""

    def __init__(self) -> None:
        self._commands: "queue.Queue[_HudCommand]" = queue.Queue()
        self._thread = threading.Thread(
            target=self._run,
            daemon=True,
            name="VoiceHudThread",
        )
        self._thread.start()

    def set_status(self, status: str, text: str = "") -> None:
        self._commands.put(_HudCommand("show", status=status, text=text))

    def hide(self) -> None:
        self._commands.put(_HudCommand("hide"))

    def stop(self) -> None:
        self._commands.put(_HudCommand("stop"))

    def _run(self) -> None:
        self._root = tk.Tk()
        self._root.withdraw()
        self._window: Optional[tk.Toplevel] = None
        self._panel: Optional[tk.Frame] = None
        self._indicator: Optional[tk.Canvas] = None
        self._label: Optional[tk.Label] = None
        self._root.after(60, self._poll_commands)
        self._root.mainloop()

    def _poll_commands(self) -> None:
        try:
            while True:
                command = self._commands.get_nowait()
                if command.action == "show":
                    self._show(command.status, command.text)
                elif command.action == "hide":
                    self._hide()
                elif command.action == "stop":
                    self._shutdown()
                    return
        except queue.Empty:
            pass

        if getattr(self, "_root", None) is not None:
            self._root.after(60, self._poll_commands)

    def _ensure_window(self) -> None:
        if self._window is not None:
            return

        self._window = tk.Toplevel(self._root)
        self._window.withdraw()
        self._window.overrideredirect(True)
        self._window.attributes("-topmost", True)
        self._window.configure(bg=_HUD_BG)

        self._panel = tk.Frame(
            self._window,
            bg=_HUD_BG,
            highlightbackground=_HUD_BORDER,
            highlightthickness=1,
            bd=0,
            padx=16,
            pady=12,
        )
        self._panel.pack()

        self._indicator = tk.Canvas(
            self._panel,
            width=18,
            height=18,
            bg=_HUD_BG,
            highlightthickness=0,
            bd=0,
        )
        self._indicator.pack(side=tk.LEFT, padx=(0, 10))

        self._label = tk.Label(
            self._panel,
            text="语音输入中",
            fg="#F4F7FB",
            bg=_HUD_BG,
            font=("Microsoft YaHei UI", 13, "bold"),
            anchor="w",
            justify=tk.LEFT,
        )
        self._label.pack(side=tk.LEFT)

    def _show(self, status: str, text: str) -> None:
        self._ensure_window()
        if self._window is None or self._indicator is None or self._label is None:
            return

        label_text = (text or "").strip() or _STATUS_TEXT.get(status, "语音状态更新")
        color = _STATUS_COLORS.get(status, "#F5A623")

        self._indicator.delete("all")
        self._indicator.create_oval(2, 2, 16, 16, fill=color, outline=color)
        self._label.config(text=label_text)

        self._window.update_idletasks()
        screen_width = self._window.winfo_screenwidth()
        screen_height = self._window.winfo_screenheight()
        width = self._window.winfo_reqwidth()
        height = self._window.winfo_reqheight()
        x = max(0, (screen_width - width) // 2)
        y = max(0, screen_height - height - 84)
        self._window.geometry(f"{width}x{height}+{x}+{y}")
        self._window.deiconify()
        self._window.lift()

    def _hide(self) -> None:
        if self._window is not None:
            self._window.withdraw()

    def _shutdown(self) -> None:
        try:
            if self._window is not None:
                self._window.destroy()
                self._window = None
        except Exception as exc:
            logger.debug(f"关闭语音悬浮窗失败: {exc}")
        root = getattr(self, "_root", None)
        self._root = None
        if root is not None:
            try:
                root.quit()
                root.destroy()
            except Exception as exc:
                logger.debug(f"销毁语音悬浮窗根窗口失败: {exc}")

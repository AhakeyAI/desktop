# coding: utf-8
"""语音阶段浮层。

作为独立子进程运行，避免打断语音客户端现有事件循环。
通过 stdin 接收 JSON 行命令，在屏幕中下方显示状态提示。
"""

from __future__ import annotations

import fcntl
import json
import os
import sys

from PySide6.QtCore import QObject, QTimer, QRectF, Qt, Signal
from PySide6.QtGui import QColor, QCursor, QFont, QGuiApplication, QPainter, QPen
from PySide6.QtWidgets import QApplication, QHBoxLayout, QLabel, QWidget

try:
    from AppKit import NSApp, NSApplicationActivationPolicyAccessory
except Exception:
    NSApp = None
    NSApplicationActivationPolicyAccessory = None


class _Spinner(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._state = "starting"
        self._angle = 0
        self._timer = QTimer(self)
        self._timer.setInterval(90)
        self._timer.timeout.connect(self._tick)
        self.setFixedSize(18, 18)

    def set_state(self, state: str) -> None:
        state = (state or "starting").strip().lower()
        self._state = state
        if state in {"starting", "processing"}:
            if not self._timer.isActive():
                self._timer.start()
        else:
            self._timer.stop()
        self.update()

    def _tick(self) -> None:
        self._angle = (self._angle + 24) % 360
        self.update()

    def paintEvent(self, event) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        rect = QRectF(3, 3, self.width() - 6, self.height() - 6)

        if self._state in {"starting", "processing"}:
            painter.setPen(QPen(QColor(255, 255, 255, 50), 2))
            painter.setBrush(Qt.NoBrush)
            painter.drawEllipse(rect)
            pen = QPen(QColor("#f4b740"), 3)
            pen.setCapStyle(Qt.RoundCap)
            painter.setPen(pen)
            painter.drawArc(rect, int(-self._angle * 16), int(120 * 16))
            return

        colors = {
            "recording": QColor("#ef5350"),
            "ready": QColor("#32b16c"),
            "error": QColor("#ff5f57"),
        }
        color = colors.get(self._state, QColor(255, 255, 255, 90))
        if self._state in colors:
            painter.setPen(Qt.NoPen)
            painter.setBrush(color)
            painter.drawEllipse(rect.adjusted(1, 1, -1, -1))
            return

        painter.setPen(QPen(color, 2))
        painter.setBrush(Qt.NoBrush)
        painter.drawEllipse(rect)


class _CommandReader(QObject):
    command_received = Signal(dict)

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self._fd = -1
        self._buffer = ""
        self._poll_timer = QTimer(self)
        self._poll_timer.setInterval(60)
        self._poll_timer.timeout.connect(self._on_poll)
        try:
            self._fd = sys.stdin.fileno()
        except Exception:
            self._fd = -1

        if self._fd >= 0:
            try:
                flags = fcntl.fcntl(self._fd, fcntl.F_GETFL)
                fcntl.fcntl(self._fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)
            except OSError:
                self._fd = -1
        if self._fd >= 0:
            self._poll_timer.start()

    def stop(self) -> None:
        self._poll_timer.stop()

    def _on_poll(self) -> None:
        try:
            chunk = os.read(self._fd, 4096)
        except OSError:
            return

        if not chunk:
            self.stop()
            self.command_received.emit({"action": "quit"})
            return

        self._buffer += chunk.decode("utf-8", errors="replace")
        while "\n" in self._buffer:
            line, self._buffer = self._buffer.split("\n", 1)
            line = line.strip()
            if not line:
                continue
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(payload, dict):
                self.command_received.emit(payload)


class VoiceHud(QWidget):
    _BOTTOM_OFFSET = 84

    def __init__(self) -> None:
        super().__init__(
            None,
            Qt.Window
            | Qt.FramelessWindowHint
            | Qt.WindowStaysOnTopHint
            | Qt.WindowDoesNotAcceptFocus
            | Qt.WindowTransparentForInput,
        )
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setAttribute(Qt.WA_ShowWithoutActivating)
        if hasattr(Qt, "WA_MacAlwaysShowToolWindow"):
            self.setAttribute(Qt.WA_MacAlwaysShowToolWindow)
        if hasattr(Qt, "WA_TransparentForMouseEvents"):
            self.setAttribute(Qt.WA_TransparentForMouseEvents)
        self.setFocusPolicy(Qt.NoFocus)
        self.setWindowOpacity(1.0)

        self._state = "starting"
        self._hide_timer = QTimer(self)
        self._hide_timer.setSingleShot(True)
        self._hide_timer.timeout.connect(self.hide)

        layout = QHBoxLayout(self)
        layout.setContentsMargins(18, 12, 18, 12)
        layout.setSpacing(10)

        self._spinner = _Spinner(self)
        layout.addWidget(self._spinner, 0, Qt.AlignVCenter)

        self._label = QLabel("语音启动中", self)
        font = QFont()
        font.setPointSize(14)
        font.setWeight(QFont.DemiBold)
        self._label.setFont(font)
        self._label.setStyleSheet("color: #f5f5f5;")
        layout.addWidget(self._label, 0, Qt.AlignVCenter)

        self.hide()

    def paintEvent(self, event) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        rect = self.rect().adjusted(1, 1, -1, -1)
        bg = QColor(24, 28, 34, 224)
        border = {
            "recording": QColor("#ef5350"),
            "ready": QColor("#32b16c"),
            "error": QColor("#ff5f57"),
        }.get(self._state, QColor("#f4b740"))
        painter.setPen(QPen(border, 1.2))
        painter.setBrush(bg)
        painter.drawRoundedRect(rect, 18, 18)

    def _reposition(self) -> None:
        screen = QGuiApplication.screenAt(QCursor.pos()) or QGuiApplication.primaryScreen()
        if screen is None:
            return
        geo = screen.availableGeometry()
        self.adjustSize()
        x = geo.x() + (geo.width() - self.width()) // 2
        y = geo.y() + geo.height() - self.height() - self._BOTTOM_OFFSET
        self.move(x, y)

    def show_status(self, state: str, text: str, timeout_ms: int = 0) -> None:
        self._state = (state or "processing").strip().lower()
        self._spinner.set_state(self._state)
        self._label.setText((text or "").strip() or "处理中")
        self._reposition()
        self.show()
        self.raise_()
        self.activateWindow()
        if timeout_ms > 0:
            self._hide_timer.start(int(timeout_ms))
        else:
            self._hide_timer.stop()
        self.update()


def main() -> int:
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    if NSApp is not None and NSApplicationActivationPolicyAccessory is not None:
        try:
            NSApp.setActivationPolicy_(NSApplicationActivationPolicyAccessory)
        except Exception:
            pass

    hud = VoiceHud()
    reader = _CommandReader(app)

    def handle_command(payload: dict) -> None:
        action = (payload.get("action") or "show").strip().lower()
        if action == "quit":
            app.quit()
            return
        if action == "hide":
            hud.hide()
            return
        hud.show_status(
            payload.get("status") or "processing",
            payload.get("text") or "处理中",
            int(payload.get("timeout_ms") or 0),
        )

    reader.command_received.connect(handle_command)
    app.aboutToQuit.connect(reader.stop)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())

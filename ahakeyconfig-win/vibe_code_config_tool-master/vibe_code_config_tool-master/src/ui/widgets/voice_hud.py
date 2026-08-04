"""语音状态悬浮窗。"""

from PySide6.QtCore import QRectF, QTimer, Qt
from PySide6.QtGui import QColor, QCursor, QGuiApplication, QPainter, QPen
from PySide6.QtWidgets import QFrame, QHBoxLayout, QLabel, QVBoxLayout, QWidget

_HUD_DEFAULT_TEXT = {
    "starting": "语音启动中",
    "recording": "录音中",
    "processing": "处理中",
    "ready": "语音已就绪",
    "error": "语音异常",
    "stopping": "语音关闭中",
}


class _HudStatusGlyph(QWidget):
    """HUD 左侧状态图形。"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._status = "starting"
        self._angle = 0
        self._timer = QTimer(self)
        self._timer.setInterval(80)
        self._timer.timeout.connect(self._advance_spinner)
        self.setFixedSize(18, 18)

    def set_status(self, status: str) -> None:
        self._status = status or "starting"
        if self._status in {"starting", "processing", "stopping"}:
            if not self._timer.isActive():
                self._timer.start()
        else:
            self._timer.stop()
            self._angle = 0
        self.update()

    def _advance_spinner(self) -> None:
        self._angle = (self._angle + 30) % 360
        self.update()

    def paintEvent(self, event) -> None:
        del event
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing, True)
        rect = QRectF(2, 2, self.width() - 4, self.height() - 4)

        if self._status in {"starting", "processing", "stopping"}:
            painter.setBrush(Qt.NoBrush)
            painter.setPen(QPen(QColor("#5C6470"), 1.8))
            painter.drawEllipse(rect)
            pen = QPen(QColor("#F5A623"), 2.4)
            pen.setCapStyle(Qt.RoundCap)
            painter.setPen(pen)
            painter.drawArc(rect, int(-self._angle * 16), int(-120 * 16))
            return

        if self._status == "ready":
            color = QColor("#2ECC71")
        else:
            color = QColor("#E74C3C")
        painter.setPen(Qt.NoPen)
        painter.setBrush(color)
        painter.drawEllipse(rect)


class VoiceHud(QWidget):
    """独立的轻量语音悬浮窗。"""

    def __init__(self, parent=None):
        flags = Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
        super().__init__(parent, flags)
        self.setAttribute(Qt.WA_TranslucentBackground, True)
        self.setAttribute(Qt.WA_ShowWithoutActivating, True)
        self.setAttribute(Qt.WA_TransparentForMouseEvents, True)
        self.setFocusPolicy(Qt.NoFocus)
        self._hide_timer = QTimer(self)
        self._hide_timer.setSingleShot(True)
        self._hide_timer.timeout.connect(self.hide)
        self._setup_ui()

    def _setup_ui(self) -> None:
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)

        self._panel = QFrame(self)
        self._panel.setObjectName("voiceHudPanel")
        self._panel.setStyleSheet(
            "QFrame#voiceHudPanel {"
            " background-color: rgba(20, 24, 30, 220);"
            " border: 1px solid rgba(255, 255, 255, 30);"
            " border-radius: 22px;"
            "}"
        )
        self._panel.setMinimumHeight(44)

        row = QHBoxLayout(self._panel)
        row.setContentsMargins(18, 10, 18, 10)
        row.setSpacing(12)

        self._glyph = _HudStatusGlyph(self._panel)
        row.addWidget(self._glyph, alignment=Qt.AlignVCenter)

        self._label = QLabel("语音启动中", self._panel)
        self._label.setStyleSheet("color: #F4F7FB; font-size: 14px; font-weight: 600;")
        row.addWidget(self._label, alignment=Qt.AlignVCenter)

        root.addWidget(self._panel)
        self.adjustSize()

    def set_status(self, status: str, text: str = "", auto_hide_ms: int = 0) -> None:
        self._hide_timer.stop()
        self._glyph.set_status(status)
        self._label.setText(text or _HUD_DEFAULT_TEXT.get(status, "语音状态更新"))
        self._reposition()
        self.show()
        self.raise_()
        if auto_hide_ms > 0:
            self._hide_timer.start(auto_hide_ms)

    def hide_now(self) -> None:
        self._hide_timer.stop()
        self.hide()

    def _reposition(self) -> None:
        screen = QGuiApplication.screenAt(QCursor.pos())
        if screen is None:
            screen = QGuiApplication.primaryScreen()
        if screen is None:
            return

        self.adjustSize()
        geo = screen.availableGeometry()
        x = geo.x() + max(0, (geo.width() - self.width()) // 2)
        y = geo.y() + max(0, geo.height() - self.height() - 84)
        self.move(x, y)

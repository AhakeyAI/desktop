"""顶部连接栏。"""

from PySide6.QtCore import QRectF, Qt, QTimer, Signal
from PySide6.QtGui import QColor, QPainter, QPen
from PySide6.QtWidgets import QFrame, QHBoxLayout, QLabel, QLineEdit, QPushButton, QWidget

from .help_button import HelpButton


class _VoiceStatusLamp(QWidget):
    """语音服务状态灯。"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._state = "stopped"
        self._angle = 0
        self._timer = QTimer(self)
        self._timer.setInterval(90)
        self._timer.timeout.connect(self._advance)
        self.setFixedSize(18, 18)

    def set_state(self, state: str) -> None:
        state = (state or "stopped").strip().lower()
        if state == self._state:
            return
        self._state = state
        if state in {"starting", "stopping", "processing"}:
            if not self._timer.isActive():
                self._timer.start()
        else:
            self._timer.stop()
        self.update()

    def _advance(self) -> None:
        self._angle = (self._angle + 24) % 360
        self.update()

    def paintEvent(self, event) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        rect = QRectF(3, 3, self.width() - 6, self.height() - 6)

        if self._state in {"starting", "stopping", "processing"}:
            painter.setPen(QPen(QColor("#c9c9c9"), 2))
            painter.setBrush(Qt.NoBrush)
            painter.drawEllipse(rect)

            pen = QPen(QColor("#f6a623"), 3)
            pen.setCapStyle(Qt.RoundCap)
            painter.setPen(pen)
            painter.drawArc(rect, int(-self._angle * 16), int(120 * 16))
            return

        if self._state == "recording":
            color = QColor("#ef5350")
            painter.setPen(Qt.NoPen)
            painter.setBrush(color)
            painter.drawEllipse(rect.adjusted(1, 1, -1, -1))
            return

        if self._state == "ready":
            color = QColor("#2e7d32")
            painter.setPen(Qt.NoPen)
            painter.setBrush(color)
            painter.drawEllipse(rect.adjusted(1, 1, -1, -1))
            return

        if self._state == "error":
            color = QColor("#d32f2f")
            painter.setPen(Qt.NoPen)
            painter.setBrush(color)
            painter.drawEllipse(rect.adjusted(1, 1, -1, -1))
            return

        painter.setPen(QPen(QColor("#9e9e9e"), 2))
        painter.setBrush(Qt.NoBrush)
        painter.drawEllipse(rect)


class ConnectionBar(QFrame):
    """设备连接与语音工具启动栏。"""

    connect_requested = Signal(str, int)
    disconnect_requested = Signal()
    start_voice_stack_requested = Signal()
    stop_voice_stack_requested = Signal()
    typeless_toggled = Signal(bool)
    audio_cue_toggled = Signal(bool)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("connectionBar")
        self._connected = False
        self._voice_running = False
        self._voice_status = "stopped"
        self._typeless_enabled = False
        self._audio_cue_enabled = True
        self._setup_ui()
        self.set_voice_status("stopped")

    def _setup_ui(self):
        layout = QHBoxLayout(self)
        layout.setContentsMargins(8, 4, 8, 4)
        layout.setSpacing(8)

        layout.addWidget(QLabel("IP:"))

        self.host_edit = QLineEdit("127.0.0.1")
        self.host_edit.setFixedSize(118, 30)
        layout.addWidget(self.host_edit)

        layout.addWidget(QLabel("Port:"))

        self.port_edit = QLineEdit("9000")
        self.port_edit.setFixedSize(64, 30)
        layout.addWidget(self.port_edit)

        self.connect_btn = QPushButton("连接")
        self.connect_btn.setFixedSize(78, 30)
        self.connect_btn.clicked.connect(self._on_click)
        layout.addWidget(self.connect_btn)

        self.start_voice_btn = QPushButton("启动语音输入")
        self.start_voice_btn.setFixedSize(120, 30)
        self.start_voice_btn.clicked.connect(self._on_voice_click)
        layout.addWidget(self.start_voice_btn)

        self.voice_help_btn = HelpButton(
            "语音输入说明",
            "单纯语音转文字不收费。\n\n"
            "如果你只是使用本地语音识别，把说话内容转换成文字，可以直接使用。\n\n"
            "只有在启用 AhaType 后，识别结果才会再经过云端整理和润色。",
            self,
            tooltip="查看语音输入的计费与使用说明",
        )
        layout.addWidget(self.voice_help_btn)

        self.voice_status_lamp = _VoiceStatusLamp()
        layout.addWidget(self.voice_status_lamp)

        self.voice_status_label = QLabel("语音未启动")
        self.voice_status_label.setMinimumWidth(92)
        layout.addWidget(self.voice_status_label)

        self.audio_cue_btn = QPushButton("关提示音")
        self.audio_cue_btn.setFixedSize(94, 30)
        self.audio_cue_btn.setToolTip("控制开始录音和结束录音时的提示音")
        self.audio_cue_btn.clicked.connect(self._on_audio_cue_click)
        layout.addWidget(self.audio_cue_btn)

        self.typeless_btn = QPushButton("启动AhaType")
        self.typeless_btn.setFixedSize(120, 30)
        self.typeless_btn.setToolTip("开启后，识别结果将经云端 AhaType 处理（需登录且服务端已实现接口）")
        self.typeless_btn.clicked.connect(self._on_typeless_click)
        layout.addWidget(self.typeless_btn)

        self.typeless_help_btn = HelpButton(
            "AhaType 说明",
            "AhaType 会把语音识别结果再做一次整理和润色。\n\n"
            "适合用于口语转书面语、补全标点，或让输入内容更适合直接发送和记录。\n\n"
            "使用前需要先登录，并且云端服务可用。",
            self,
            tooltip="查看 AhaType 的说明和使用场景",
        )
        layout.addWidget(self.typeless_help_btn)

        layout.addStretch()

    def set_typeless_enabled(self, enabled: bool):
        self._typeless_enabled = bool(enabled)
        self._update_typeless_button_text()

    def set_audio_cue_enabled(self, enabled: bool) -> None:
        self._audio_cue_enabled = bool(enabled)
        self._update_audio_cue_button_text()

    def _on_typeless_click(self):
        self._typeless_enabled = not self._typeless_enabled
        self._update_typeless_button_text()
        self.typeless_toggled.emit(self._typeless_enabled)

    def _update_typeless_button_text(self):
        if self._typeless_enabled:
            self.typeless_btn.setText("关闭AhaType")
        else:
            self.typeless_btn.setText("启动AhaType")

    def _on_audio_cue_click(self) -> None:
        self._audio_cue_enabled = not self._audio_cue_enabled
        self._update_audio_cue_button_text()
        self.audio_cue_toggled.emit(self._audio_cue_enabled)

    def _update_audio_cue_button_text(self) -> None:
        self.audio_cue_btn.setText("关提示音" if self._audio_cue_enabled else "开提示音")

    def _on_click(self):
        if self._connected:
            self.disconnect_requested.emit()
            return

        host = self.host_edit.text().strip()
        port = int(self.port_edit.text().strip())
        self.connect_requested.emit(host, port)

    def set_connected(self, connected: bool):
        self._connected = connected
        if connected:
            self.connect_btn.setText("断开")
            self.host_edit.setEnabled(False)
            self.port_edit.setEnabled(False)
        else:
            self.connect_btn.setText("连接")
            self.host_edit.setEnabled(True)
            self.port_edit.setEnabled(True)
    def _on_voice_click(self):
        """点击语音按钮时，根据当前状态发出不同信号"""
        if self._voice_running:
            self.stop_voice_stack_requested.emit()
        else:
            self.start_voice_stack_requested.emit()

    def set_voice_running(self, running: bool):
        """由主窗口调用，用于切换按钮文字和状态"""
        self._voice_running = running
        if running:
            self.start_voice_btn.setText("停止语音输入")
        else:
            self.start_voice_btn.setText("启动语音输入")

    def set_voice_status(self, status: str, detail: str | None = None) -> None:
        self._voice_status = (status or "stopped").strip().lower()
        self.voice_status_lamp.set_state(self._voice_status)

        defaults = {
            "stopped": ("语音未启动", "#9e9e9e"),
            "starting": ("语音启动中", "#f6a623"),
            "recording": ("录音中", "#ef5350"),
            "processing": ("处理中", "#f6a623"),
            "ready": ("语音已就绪", "#2e7d32"),
            "stopping": ("语音关闭中", "#f6a623"),
            "error": ("语音异常", "#d32f2f"),
        }
        text, color = defaults.get(self._voice_status, defaults["stopped"])
        if detail:
            text = detail
        self.voice_status_label.setText(text)
        self.voice_status_label.setStyleSheet(
            f"color: {color}; font-weight: 600;"
        )

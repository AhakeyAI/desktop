"""Qt-based Hook manager UI shared by Windows/macOS builds."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Callable

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QFont, QIcon
from PySide6.QtWidgets import (
    QApplication,
    QFrame,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)


Action = Callable[[], str]
StateProvider = Callable[[], dict]


def _load_icon(icon_path: str | None) -> QIcon:
    if not icon_path:
        return QIcon()
    path = Path(icon_path)
    if not path.is_file():
        return QIcon()
    return QIcon(str(path))


class HookManagerWindow(QMainWindow):
    def __init__(
        self,
        *,
        window_title: str,
        state_provider: StateProvider,
        install_claude: Action,
        uninstall_claude: Action,
        install_cursor: Action,
        uninstall_cursor: Action,
        icon_path: str | None = None,
    ) -> None:
        super().__init__()
        self._state_provider = state_provider
        self._install_claude = install_claude
        self._uninstall_claude = uninstall_claude
        self._install_cursor = install_cursor
        self._uninstall_cursor = uninstall_cursor

        self.setWindowTitle(window_title)
        self.setWindowIcon(_load_icon(icon_path))
        self.resize(1024, 900)
        self.setMinimumSize(980, 860)

        self._build_ui()
        self.refresh_status()

    def _build_ui(self) -> None:
        central = QWidget(self)
        self.setCentralWidget(central)

        root = QVBoxLayout(central)
        root.setContentsMargins(20, 18, 20, 20)
        root.setSpacing(16)

        status_group = QGroupBox("当前状态")
        status_layout = QVBoxLayout(status_group)
        status_layout.setContentsMargins(18, 24, 18, 18)
        status_layout.setSpacing(12)

        self.mode_label = QLabel()
        self.path_label = QLabel()
        self.claude_status_label = QLabel()
        self.cursor_status_label = QLabel()

        for label in (
            self.mode_label,
            self.path_label,
            self.claude_status_label,
            self.cursor_status_label,
        ):
            label.setWordWrap(True)
            label.setStyleSheet("font-size: 16px; color: #111;")
            status_layout.addWidget(label)

        root.addWidget(status_group)

        actions_frame = QFrame()
        actions_layout = QGridLayout(actions_frame)
        actions_layout.setContentsMargins(8, 0, 8, 0)
        actions_layout.setHorizontalSpacing(24)
        actions_layout.setVerticalSpacing(18)

        label_font = QFont()
        label_font.setPointSize(16)

        claude_label = QLabel("Claude:")
        claude_label.setFont(label_font)
        cursor_label = QLabel("Cursor:")
        cursor_label.setFont(label_font)

        actions_layout.addWidget(claude_label, 0, 0, alignment=Qt.AlignVCenter)
        actions_layout.addWidget(cursor_label, 1, 0, alignment=Qt.AlignVCenter)

        self.install_claude_button = self._build_action_button("安装 Hooks", "#4CAF50")
        self.uninstall_claude_button = self._build_action_button("卸载 Hooks", "#F44336")
        self.install_cursor_button = self._build_action_button("安装 Hooks", "#2196F3")
        self.uninstall_cursor_button = self._build_action_button("卸载 Hooks", "#FF9800")

        self.install_claude_button.clicked.connect(lambda: self._run_action(self._install_claude))
        self.uninstall_claude_button.clicked.connect(lambda: self._run_action(self._uninstall_claude))
        self.install_cursor_button.clicked.connect(lambda: self._run_action(self._install_cursor))
        self.uninstall_cursor_button.clicked.connect(lambda: self._run_action(self._uninstall_cursor))

        actions_layout.addWidget(self.install_claude_button, 0, 1)
        actions_layout.addWidget(self.uninstall_claude_button, 0, 2)
        actions_layout.addWidget(self.install_cursor_button, 1, 1)
        actions_layout.addWidget(self.uninstall_cursor_button, 1, 2)
        actions_layout.setColumnStretch(3, 1)

        root.addWidget(actions_frame)

        output_group = QGroupBox("输出")
        output_layout = QVBoxLayout(output_group)
        output_layout.setContentsMargins(12, 22, 12, 12)

        self.output_text = QPlainTextEdit()
        self.output_text.setReadOnly(True)
        self.output_text.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.output_text.setStyleSheet(
            "QPlainTextEdit { background: white; border: 1px solid #c7c7c7; font-size: 14px; }"
        )
        output_layout.addWidget(self.output_text)
        root.addWidget(output_group, 1)

        footer = QHBoxLayout()
        footer.addStretch(1)
        close_button = QPushButton("关闭")
        close_button.setFixedSize(140, 42)
        close_button.clicked.connect(self.close)
        footer.addWidget(close_button)
        root.addLayout(footer)

    @staticmethod
    def _build_action_button(text: str, color: str) -> QPushButton:
        button = QPushButton(text)
        button.setFixedSize(220, 92)
        button.setStyleSheet(
            "QPushButton {"
            f" background: {color};"
            " color: white;"
            " border: 2px solid #222;"
            " font-size: 18px;"
            " font-weight: 600;"
            "}"
            "QPushButton:hover { border-color: #111; }"
            "QPushButton:pressed { padding-top: 2px; }"
        )
        return button

    def append_output(self, message: str) -> None:
        existing = self.output_text.toPlainText().strip()
        next_text = message.strip() if not existing else existing + "\n\n" + message.strip()
        self.output_text.setPlainText(next_text)
        self.output_text.verticalScrollBar().setValue(self.output_text.verticalScrollBar().maximum())

    def refresh_status(self) -> None:
        state = self._state_provider()
        self.mode_label.setText(f"运行模式:  {state['mode_text']}")
        self.path_label.setText(f"程序路径:  {state['self_path']}")
        self.claude_status_label.setText(
            "Claude Hook 状态: " + ("已安装" if state["claude_installed"] else "未安装")
        )
        self.cursor_status_label.setText(
            "Cursor Hook 状态: " + ("已安装" if state["cursor_installed"] else "未安装")
        )

    def _run_action(self, action: Action) -> None:
        try:
            result = action()
        except Exception as exc:
            QMessageBox.critical(self, "执行失败", str(exc))
            self.append_output(f"执行失败: {exc}")
            self.refresh_status()
            return

        self.append_output(result)
        self.refresh_status()


def run_hook_manager(
    *,
    window_title: str,
    state_provider: StateProvider,
    install_claude: Action,
    uninstall_claude: Action,
    install_cursor: Action,
    uninstall_cursor: Action,
    icon_path: str | None = None,
) -> int:
    app = QApplication.instance()
    owns_app = app is None
    if app is None:
        app = QApplication(sys.argv)
        app.setStyle("Fusion")
        app.setQuitOnLastWindowClosed(True)

    window = HookManagerWindow(
        window_title=window_title,
        state_provider=state_provider,
        install_claude=install_claude,
        uninstall_claude=uninstall_claude,
        install_cursor=install_cursor,
        uninstall_cursor=uninstall_cursor,
        icon_path=icon_path,
    )
    window.show()
    window.raise_()
    window.activateWindow()
    QTimer.singleShot(0, window.raise_)
    QTimer.singleShot(0, window.activateWindow)

    if owns_app:
        return app.exec()
    return 0

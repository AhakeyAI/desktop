"""轻量级帮助说明按钮。"""

from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QMessageBox, QToolButton, QWidget


class HelpButton(QToolButton):
    """点击后弹出简短说明的问号按钮。"""

    def __init__(
        self,
        title: str,
        body: str,
        parent: QWidget | None = None,
        *,
        tooltip: str | None = None,
    ) -> None:
        super().__init__(parent)
        self._title = title
        self._body = body
        self.setText("?")
        self.setCursor(Qt.PointingHandCursor)
        self.setFixedSize(18, 18)
        self.setAutoRaise(True)
        self.setToolTip(tooltip or title)
        self.setStyleSheet(
            """
            QToolButton {
                border: 1px solid #c8ccd4;
                border-radius: 9px;
                background: #f5f7fa;
                color: #607080;
                font-weight: 700;
            }
            QToolButton:hover {
                background: #e9eef5;
                color: #314252;
                border-color: #adb8c5;
            }
            """
        )
        self.clicked.connect(self._show_help)

    def _show_help(self) -> None:
        QMessageBox.information(self, self._title, self._body)

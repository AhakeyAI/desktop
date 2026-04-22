"""通用问号说明按钮。"""

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QMessageBox, QPushButton


class HelpButton(QPushButton):
    """点击后弹出轻量说明框的小问号按钮。"""

    def __init__(self, title: str, body: str, parent=None):
        super().__init__("?", parent)
        self._dialog_title = title
        self._dialog_body = body
        self.setCursor(Qt.PointingHandCursor)
        self.setFixedSize(22, 22)
        self.setToolTip(title)
        self.setStyleSheet(
            "QPushButton {"
            " border: 1px solid rgba(255, 255, 255, 0.28);"
            " border-radius: 11px;"
            " background-color: rgba(255, 255, 255, 0.04);"
            " color: #D8DDE6;"
            " font-weight: 700;"
            " padding: 0px;"
            "}"
            "QPushButton:hover {"
            " background-color: rgba(255, 255, 255, 0.12);"
            " border-color: rgba(255, 255, 255, 0.42);"
            "}"
            "QPushButton:pressed {"
            " background-color: rgba(255, 255, 255, 0.18);"
            "}"
        )
        self.clicked.connect(self._show_help)

    def _show_help(self) -> None:
        QMessageBox.information(self, self._dialog_title, self._dialog_body)

"""
模式选择器控件 — Mode 0/1/2 切换
"""

from PySide6.QtWidgets import QFrame, QHBoxLayout, QPushButton, QButtonGroup
from PySide6.QtCore import Signal

from ..styles import MODE_SELECTOR_STYLE


class ModeSelector(QFrame):
    """模式切换按钮组"""

    mode_changed = Signal(int)  # mode_id: 0, 1, 2

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(MODE_SELECTOR_STYLE)
        self._setup_ui()

    def _setup_ui(self):
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        self._btn_group = QButtonGroup(self)
        self._btn_group.setExclusive(True)
        self._buttons: list[QPushButton] = []

        for i in range(3):
            btn = QPushButton(f"Mode {i}")
            btn.setProperty("class", "modeBtn")
            btn.setCheckable(True)
            btn.setFlat(True)
            self._btn_group.addButton(btn, i)
            self._buttons.append(btn)
            layout.addWidget(btn)

        self._buttons[0].setChecked(True)

        self._btn_group.idClicked.connect(self.mode_changed)

    def set_mode(self, mode_id: int):
        """从外部设置当前模式"""
        if 0 <= mode_id < len(self._buttons):
            self._buttons[mode_id].setChecked(True)

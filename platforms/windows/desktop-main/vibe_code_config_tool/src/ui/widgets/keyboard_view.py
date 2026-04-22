"""
键盘视图控件 — 4键布局可视化
"""

from PySide6.QtWidgets import QFrame, QHBoxLayout, QPushButton, QButtonGroup
from PySide6.QtCore import Signal

from ..styles import KEY_BUTTON_STYLE


class KeyboardView(QFrame):
    """4键键盘可视化，点击选中某个键"""

    key_selected = Signal(int)  # key_index: 0-3

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(KEY_BUTTON_STYLE)
        self._setup_ui()

    def _setup_ui(self):
        layout = QHBoxLayout(self)
        layout.setSpacing(12)

        self._btn_group = QButtonGroup(self)
        self._btn_group.setExclusive(True)
        self._buttons: list[QPushButton] = []

        for i in range(4):
            btn = QPushButton(f"Key {i + 1}\n---")
            btn.setProperty("class", "keyBtn")
            btn.setCheckable(True)
            self._btn_group.addButton(btn, i)
            self._buttons.append(btn)
            layout.addWidget(btn)

        self._buttons[0].setChecked(True)
        self._btn_group.idClicked.connect(self.key_selected)

    def update_key_labels(self, labels: list[str]):
        """更新所有按键显示的标签"""
        for i, label in enumerate(labels):
            if i < len(self._buttons):
                self._buttons[i].setText(f"Key {i + 1}\n{label}")

    def selected_key(self) -> int:
        return self._btn_group.checkedId()

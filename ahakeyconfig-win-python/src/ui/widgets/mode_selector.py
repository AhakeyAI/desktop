"""模式选择器控件 - Mode 0/1/2 切换"""

from PySide6.QtCore import Signal
from PySide6.QtWidgets import QButtonGroup, QFrame, QHBoxLayout, QPushButton

from ..styles import MODE_SELECTOR_STYLE
from .help_button import HelpButton


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

        self.mode_help_btn = HelpButton(
            "模式说明",
            "软件里的 Mode 0 / Mode1 / Mode 2，分别对应键盘上的左数 1、2 灯亮 / 3、4 灯亮 / 5、6 灯亮。\n\n"
            "单击电源键切换模式。\n\n"
            "你当前切换到哪个 Mode，修改的就是键盘对应模式下的按键功能和动画配置。\n\n"
            "点击连接后，就可以修改当前模式下的按键和动画配置。",
        )
        layout.addWidget(self.mode_help_btn)

        self._buttons[0].setChecked(True)
        layout.addStretch()

        self._btn_group.idClicked.connect(self.mode_changed)

    def set_mode(self, mode_id: int):
        """从外部设置当前模式"""
        if 0 <= mode_id < len(self._buttons):
            self._buttons[mode_id].setChecked(True)

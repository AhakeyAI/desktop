"""顶部设备信息栏。"""

from PySide6.QtCore import Signal
from PySide6.QtWidgets import QFrame, QHBoxLayout, QLabel, QPushButton


class DeviceInfoBar(QFrame):
    """展示设备状态摘要。"""

    refresh_requested = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._setup_ui()

    def _setup_ui(self):
        layout = QHBoxLayout(self)
        layout.setContentsMargins(8, 2, 8, 2)

        self._labels = {}
        fields = [
            ("battery", "电量"),
            ("signal", "信号"),
            ("fw_main", "固件主版本"),
            ("fw_sub", "固件子版本"),
            ("work_mode", "工作模式"),
            ("ble_status", "BLE"),
        ]

        for key, name in fields:
            label = QLabel(f"{name}: --")
            label.setStyleSheet("font-size: 12px; color: #aaa; margin-right: 12px;")
            self._labels[key] = label
            layout.addWidget(label)

        layout.addStretch()

        refresh_btn = QPushButton("刷新")
        refresh_btn.setFixedWidth(60)
        refresh_btn.clicked.connect(self.refresh_requested)
        layout.addWidget(refresh_btn)

    def update_device_info(self, info: dict):
        mapping = {
            "battery": ("BatteryLevel", "电量", "%"),
            "signal": ("SignalStrength", "信号", ""),
            "fw_main": ("FwMain", "固件主版本", ""),
            "fw_sub": ("FwSub", "固件子版本", ""),
            "work_mode": ("WorkMode", "工作模式", ""),
        }
        for key, (info_key, name, unit) in mapping.items():
            value = info.get(info_key, "--")
            self._labels[key].setText(f"{name}: {value}{unit}")

    def update_ble_status(self, info: dict):
        if info.get("connected"):
            name = info.get("name", "Unknown")
            self._labels["ble_status"].setText(f"BLE: {name} (已连接)")
            self._labels["ble_status"].setStyleSheet(
                "font-size: 12px; color: #4caf50; margin-right: 12px;"
            )
        else:
            self._labels["ble_status"].setText("BLE: 未连接")
            self._labels["ble_status"].setStyleSheet(
                "font-size: 12px; color: #f44336; margin-right: 12px;"
            )

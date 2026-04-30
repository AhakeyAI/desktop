"""
设备信息页 — 显示设备详情和通信日志
"""

from datetime import datetime
import struct

from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QGroupBox, QGridLayout, QLabel,
    QTextEdit, QPushButton, QHBoxLayout, QLineEdit, QComboBox,
    QMessageBox,
)
from PySide6.QtCore import Qt

from ...comm.protocol import DeviceCmd, BLE_APPEARANCE


class DevicePage(QWidget):
    """设备信息和调试日志页"""

    def __init__(self, device_state=None, parent=None):
        super().__init__(parent)
        self._device_state = device_state  # 保存 DeviceState 引用
        self._setup_ui()

    def _setup_ui(self):
        layout = QVBoxLayout(self)

        # ========== 设备信息 ==========
        info_group = QGroupBox("设备信息")
        info_layout = QGridLayout(info_group)

        self._info_labels = {}
        fields = [
            (0, 0, "battery", "电量"),
            (0, 1, "signal", "信号强度"),
            (0, 2, "fw_main", "固件主版本"),
            (0, 3, "fw_sub", "固件子版本"),
            (1, 0, "work_mode", "工作模式"),
            (1, 1, "light_mode", "灯光模式"),
            (1, 2, "switch_state", "开关状态"),
        ]

        for row, col, key, name in fields:
            lbl_name = QLabel(f"{name}:")
            lbl_name.setStyleSheet("color: #888;")
            lbl_val = QLabel("--")
            lbl_val.setStyleSheet("font-weight: bold;")
            info_layout.addWidget(lbl_name, row, col * 2)
            info_layout.addWidget(lbl_val, row, col * 2 + 1)
            self._info_labels[key] = lbl_val

        layout.addWidget(info_group)

        # ========== BLE 状态 ==========
        ble_group = QGroupBox("BLE 连接状态")
        ble_layout = QGridLayout(ble_group)

        self._ble_labels = {}
        for col, (key, name) in enumerate([
            ("connected", "连接"), ("name", "设备名"),
            ("mac", "MAC地址"), ("is_target", "目标设备"),
        ]):
            lbl_name = QLabel(f"{name}:")
            lbl_name.setStyleSheet("color: #888;")
            lbl_val = QLabel("--")
            lbl_val.setStyleSheet("font-weight: bold;")
            ble_layout.addWidget(lbl_name, 0, col * 2)
            ble_layout.addWidget(lbl_val, 0, col * 2 + 1)
            self._ble_labels[key] = lbl_val

        layout.addWidget(ble_group)

        # ========== 设备设置 ==========
        settings_group = QGroupBox("设备设置")
        settings_layout = QGridLayout(settings_group)

        # 设备名字
        settings_layout.addWidget(QLabel("设备名字:"), 0, 0)
        self.name_input = QLineEdit()
        self.name_input.setPlaceholderText("最长21字节（UTF-8）")
        self.name_input.setMaxLength(50)  # UI 限制，实际会在应用时验证字节数
        settings_layout.addWidget(self.name_input, 0, 1)

        # 设备外观
        settings_layout.addWidget(QLabel("设备外观:"), 1, 0)
        self.appearance_combo = QComboBox()
        for name in BLE_APPEARANCE.keys():
            self.appearance_combo.addItem(name)
        settings_layout.addWidget(self.appearance_combo, 1, 1)

        # 应用按钮
        apply_btn = QPushButton("应用设置")
        apply_btn.setStyleSheet(
            "background-color: #2e7d32; color: white; font-weight: bold; "
            "padding: 6px 16px;"
        )
        apply_btn.clicked.connect(self._apply_settings)
        settings_layout.addWidget(apply_btn, 2, 0, 1, 2)

        layout.addWidget(settings_group)

        # ========== 通信日志 ==========
        log_group = QGroupBox("通信日志")
        log_layout = QVBoxLayout(log_group)

        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        self.log_text.setStyleSheet("font-family: Consolas, monospace; font-size: 11px;")
        log_layout.addWidget(self.log_text)

        btn_row = QHBoxLayout()
        clear_btn = QPushButton("清空日志")
        clear_btn.clicked.connect(self.log_text.clear)
        btn_row.addStretch()
        btn_row.addWidget(clear_btn)
        log_layout.addLayout(btn_row)

        layout.addWidget(log_group)

    def update_device_info(self, info: dict):
        """更新设备信息显示"""
        mapping = {
            "battery": "BatteryLevel",
            "signal": "SignalStrength",
            "fw_main": "FwMain",
            "fw_sub": "FwSub",
            "work_mode": "WorkMode",
            "light_mode": "LightMode",
            "switch_state": "SwitchState",
        }
        for key, info_key in mapping.items():
            val = info.get(info_key, "--")
            self._info_labels[key].setText(str(val))

    def update_ble_status(self, info: dict):
        """更新 BLE 状态显示"""
        self._ble_labels["connected"].setText("已连接" if info.get("connected") else "未连接")
        self._ble_labels["name"].setText(info.get("name", "--"))
        self._ble_labels["mac"].setText(info.get("mac", "--"))
        self._ble_labels["is_target"].setText("是" if info.get("is_target") else "否")

    def log(self, message: str, level: str = "info"):
        """添加日志"""
        ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        colors = {"info": "#aaa", "send": "#4fc3f7", "recv": "#66bb6a", "error": "#f44336"}
        color = colors.get(level, "#aaa")
        self.log_text.append(f'<span style="color:{color}">{ts} &gt; {message}</span>')

    def _apply_settings(self):
        """应用设备设置（名字和外观）"""
        if not self._device_state or not self._device_state.connected:
            QMessageBox.information(self, "提示", "请先连接设备")
            return

        try:
            # 1. 设置设备名字
            name_text = self.name_input.text().strip()
            if name_text:
                name_bytes = name_text.encode("utf-8")
                if len(name_bytes) > 21:
                    QMessageBox.warning(
                        self, "名字过长",
                        f"设备名字最长支持21字节（UTF-8编码）\n"
                        f"当前: {len(name_bytes)} 字节\n\n"
                        f"请缩短名字或使用更少的字符。"
                    )
                    return
                if len(name_bytes) > 15:
                    QMessageBox.warning(
                        self, "名字有点长",
                        f"设备名字最长支持21字节，但是广播包只能显示前15字节，显示会有乱码\n"
                        f"当前: {len(name_bytes)} 字节\n\n"
                        f"建议缩短名字或使用更少的字符。"
                    )

                self._device_state.service.send_command(DeviceCmd.CHANGE_NAME, name_bytes)
                self.log(f"设置设备名字: {name_text} ({len(name_bytes)} 字节)", "send")

            # 2. 设置设备外观
            appearance_name = self.appearance_combo.currentText()
            appearance_value = BLE_APPEARANCE[appearance_name]
            appearance_bytes = struct.pack("<H", appearance_value)
            self._device_state.service.send_command(DeviceCmd.CHANGE_APPEARE, appearance_bytes)
            self.log(f"设置设备外观: {appearance_name} (0x{appearance_value:04X})", "send")

            QMessageBox.information(self, "成功", "设备设置已应用\n重启设备应用新名字\n可能需要重启ble_tcp_driver然后重新连接")

        except Exception as e:
            self.log(f"设置失败: {e}", "error")
            QMessageBox.warning(self, "设置失败", str(e))

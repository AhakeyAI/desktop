"""
设备状态中心 — 连接 UI 层与通信层的桥梁
持有所有可观察状态，通过 Qt 信号通知 UI
"""

from PySide6.QtCore import QObject, Signal

from .keymap import KeyboardConfig
from ..comm.tcp_client import TcpClient
from ..comm.device_service import DeviceService


class DeviceState(QObject):
    """中心状态管理器"""

    # 信号
    connection_changed = Signal(bool)
    ble_status_updated = Signal(dict)
    device_info_updated = Signal(dict)
    current_mode_changed = Signal(int)
    config_changed = Signal(object)
    upload_progress = Signal(int, int)
    error_occurred = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)

        self._tcp = TcpClient(self)
        self._service = DeviceService(self._tcp, self)
        self._config = KeyboardConfig()
        self._current_mode = 0
        self._connected = False

        # 连接内部信号
        self._tcp.connection_changed.connect(self._on_connection_changed)
        self._service.status_received.connect(self.ble_status_updated)
        self._service.info_received.connect(self.device_info_updated)
        self._service.upload_progress.connect(self.upload_progress)

    @property
    def tcp(self) -> TcpClient:
        return self._tcp

    @property
    def service(self) -> DeviceService:
        return self._service

    @property
    def config(self) -> KeyboardConfig:
        return self._config

    @config.setter
    def config(self, value: KeyboardConfig):
        self._config = value
        self.config_changed.emit(value)

    @property
    def current_mode(self) -> int:
        return self._current_mode

    @current_mode.setter
    def current_mode(self, value: int):
        if 0 <= value <= 2 and value != self._current_mode:
            self._current_mode = value
            self.current_mode_changed.emit(value)

    @property
    def connected(self) -> bool:
        return self._connected

    def _on_connection_changed(self, connected: bool):
        self._connected = connected
        self.connection_changed.emit(connected)

    # ==============================
    # 连接操作
    # ==============================

    def connect_device(self, host: str, port: int):
        try:
            self._tcp.open(host, port)
        except Exception as e:
            self.error_occurred.emit(f"连接失败: {e}")

    def disconnect_device(self):
        self._tcp.disconnect()

    # ==============================
    # 设备查询
    # ==============================

    def query_status(self):
        if self._connected:
            self._service.query_status()

    def query_info(self):
        if self._connected:
            self._service.query_info()

#!/usr/bin/env python3
"""
BLE TCP Bridge for Linux - PyQt5 GUI 版
功能对标 Windows 版 BLE_tcp_bridge
适配 Ubuntu 20.04
"""

import asyncio
import json
import logging
import os
import signal
import socket
import struct
import sys
import traceback
from dataclasses import dataclass, asdict
from enum import IntEnum
from pathlib import Path
from typing import Optional, List, Dict

import dbus
import dbus.service
import dbus.mainloop.glib
from PyQt5.QtCore import Qt, QTimer, pyqtSignal, QObject, QThread, QSize
from PyQt5.QtGui import QFont, QIcon, QKeyEvent, QTextCursor, QColor
from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QComboBox, QPushButton, QTextEdit, QCheckBox,
    QSystemTrayIcon, QMenu, QMessageBox, QAction
)
from gi.repository import GLib

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

CONFIG_PATH = Path.home() / ".config" / "ahakey" / "ble_bridge.json"


class PacketType(IntEnum):
    WRITE_DATA = 0x01
    WRITE_COMMAND = 0x02
    QUERY_BLE_STATUS = 0x03
    QUERY_DEVICE_INFO = 0x04
    BLE_NOTIFY = 0x81
    BLE_STATUS_RESP = 0x82
    DEVICE_INFO_RESP = 0x83


@dataclass
class AppConfig:
    ble_name: str = ""
    ble_mac: str = ""
    server_port: int = 9000
    start_minimized: bool = False

    @property
    def has_saved_device(self) -> bool:
        return bool(self.ble_name and self.ble_mac)

    def save(self):
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with open(CONFIG_PATH, 'w') as f:
            json.dump(asdict(self), f, indent=2)

    @classmethod
    def load(cls) -> 'AppConfig':
        try:
            if CONFIG_PATH.exists():
                with open(CONFIG_PATH) as f:
                    data = json.load(f)
                return cls(**data)
        except Exception as e:
            logger.warning(f"加载配置失败: {e}")
        return cls()


def build_packet(pkt_type: PacketType, data: bytes = None) -> bytes:
    length = len(data) if data else 0
    header = bytes([pkt_type, length & 0xFF, (length >> 8) & 0xFF])
    return header + (data if data else b'')


def get_local_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"


class TcpClient:
    def __init__(self, reader, writer, bridge):
        self.reader = reader
        self.writer = writer
        self.bridge = bridge
        self.addr = writer.get_extra_info('peername')

    async def handle(self):
        try:
            while True:
                header = await self.reader.readexactly(3)
                pkt_type = header[0]
                length = header[1] | (header[2] << 8)
                data = b''
                if length > 0:
                    data = await self.reader.readexactly(length)
                await self.bridge.handle_packet(self, pkt_type, data)
        except asyncio.IncompleteReadError:
            pass
        except Exception as e:
            logger.error(f"TCP client error: {e}")
        finally:
            self.bridge.remove_client(self)

    def send(self, data: bytes):
        try:
            self.writer.write(data)
        except Exception as e:
            logger.error(f"Send to {self.addr} failed: {e}")


class AsyncWorker(QThread):
    log_signal = pyqtSignal(str, str)
    device_found = pyqtSignal(str, str)
    connected_signal = pyqtSignal(str)
    disconnected_signal = pyqtSignal()
    status_update = pyqtSignal(str)
    client_count_changed = pyqtSignal(int)

    def __init__(self, config: AppConfig):
        super().__init__()
        self.config = config
        self.bus: Optional[dbus.Bus] = None
        self.device_path: Optional[str] = None
        self.device_iface = None
        self.write_char_path: Optional[str] = None
        self.notify_char_path: Optional[str] = None
        self.data_char_path: Optional[str] = None
        self.connected = False
        self.device_name = ""
        self.clients: List[TcpClient] = []
        self.running = False
        self.auto_connecting = False
        self.target_confirmed = False
        self.devices_map: Dict[str, str] = {}
        self.server = None

        self.TARGET_SERVICE = "0000ffe0-0000-1000-8000-00805f9b34fb"
        self.DEVICE_STATUS_QUERY = bytes([0xAA, 0xBB, 0x00, 0xCC, 0xDD])

    def log(self, color: str, message: str):
        self.log_signal.emit(color, message)

    def run(self):
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        self.running = True
        try:
            self.loop.run_until_complete(self.main_loop())
        except Exception as e:
            logger.error(f"Worker error: {e}")
        finally:
            self.loop.close()

    async def main_loop(self):
        try:
            dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
            self.bus = dbus.SystemBus()
        except Exception as e:
            self.log("red", f"D-Bus 连接失败: {e}")
            return

        # 启动 TCP 服务器
        await self.start_tcp_server()

        # 自动开始扫描
        self.start_scan()

        # 保持运行
        while self.running:
            await asyncio.sleep(0.1)

    def start_scan(self):
        self.devices_map.clear()
        self.log("blue", "自动扫描蓝牙设备中...")
        self.scan_devices()

        if self.config.has_saved_device:
            self.log("blue", f"目标设备: {self.config.ble_name} [{self.config.ble_mac}]")
            self.start_retry_timer()

    def scan_devices(self):
        try:
            object_manager = dbus.Interface(
                self.bus.get_object("org.bluez", "/"),
                "org.freedesktop.DBus.ObjectManager"
            )
            objects = object_manager.GetManagedObjects()

            for path, interfaces in objects.items():
                if "org.bluez.Device1" in interfaces:
                    props = interfaces["org.bluez.Device1"]
                    name = props.get("Name", "")
                    address = props.get("Address", "")

                    if not name:
                        continue

                    self.devices_map[address] = name
                    self.device_found.emit(name, address)

                    # 自动连接已保存的设备
                    if (self.config.has_saved_device
                            and not self.auto_connecting
                            and not self.connected):
                        if (name == self.config.ble_name
                                and address.upper() == self.config.ble_mac.upper()):
                            self.auto_connecting = True
                            self.log("blue", "发现目标设备, 自动连接...")
                            self.connect_to_device(path, name, address)

        except Exception as e:
            logger.error(f"Scan error: {e}")

    def connect_to_device(self, path: str, name: str, address: str):
        try:
            self.device_path = path
            self.device_name = name

            self.device_iface = dbus.Interface(
                self.bus.get_object("org.bluez", path),
                "org.bluez.Device1"
            )

            # 监听设备属性变化（Connected, ServicesResolved 等）
            self.bus.add_signal_receiver(
                self.on_properties_changed,
                signal_name="PropertiesChanged",
                dbus_interface="org.freedesktop.DBus.Properties",
                path=path
            )
            # 注意：特征值变化监听在 _subscribe_notify 中注册，因为特征路径在发现服务后才确定

            self.device_iface.Connect(
                reply_handler=lambda: self._on_connect_reply(),
                error_handler=lambda e: self._on_connect_error(e)
            )
        except Exception as e:
            self.log("red", f"连接失败: {e}")
            self.auto_connecting = False

    def _on_connect_reply(self):
        self.connected = True
        self.log("blue", f"Connected: {self.device_name}")
        self.connected_signal.emit(self.device_name)
        # 检查 GATT 服务是否已就绪
        try:
            props = dbus.Interface(
                self.bus.get_object("org.bluez", self.device_path),
                "org.freedesktop.DBus.Properties"
            )
            services_resolved = bool(props.Get("org.bluez.Device1", "ServicesResolved"))
            if services_resolved:
                self.discover_services()
            else:
                self.log("blue", "等待 GATT 服务发现...")
                # 服务发现就绪后会在 on_properties_changed 中触发
        except Exception as e:
            logger.error(f"Check ServicesResolved error: {e}")
            self.discover_services()

    def _on_connect_error(self, error):
        self.log("red", f"BLE 连接失败: {error}")
        self.connected = False
        self.auto_connecting = False
        self.start_retry_timer()

    def discover_services(self):
        try:
            object_manager = dbus.Interface(
                self.bus.get_object("org.bluez", "/"),
                "org.freedesktop.DBus.ObjectManager"
            )
            objects = object_manager.GetManagedObjects()

            service_path = None
            for path, interfaces in objects.items():
                if "org.bluez.GattService1" in interfaces:
                    props = interfaces["org.bluez.GattService1"]
                    uuid = props.get("UUID", "").lower()
                    if uuid == self.TARGET_SERVICE.lower():
                        service_path = path
                        break

            if not service_path:
                self.log("orange", "未找到目标服务，重试中...")
                # 如果服务已就绪但找不到，可能是设备未配对，尝试重试
                self._retry_discover_services(3)
                return

            self.log("blue", f"发现目标服务")

            # 查找特征
            for path, interfaces in objects.items():
                if path.startswith(service_path) and "org.bluez.GattCharacteristic1" in interfaces:
                    char_props = interfaces["org.bluez.GattCharacteristic1"]
                    char_uuid = char_props.get("UUID", "").lower()
                    flags = char_props.get("Flags", [])

                    # AhaKey 使用同一个 UUID 的不同 handle，这里简化处理
                    if "write" in flags or "write-without-response" in flags:
                        self.write_char_path = path
                        self.log("green", "  -> 命令特征已就绪")
                    if "notify" in flags or "indicate" in flags:
                        self.notify_char_path = path
                        self.log("green", "  -> 通知特征已就绪")

            # 启用通知
            if self.notify_char_path:
                self._subscribe_notify(self.notify_char_path)

            # 确认目标设备
            if self.write_char_path and self.notify_char_path:
                self.target_confirmed = True
                self.save_device_config()
                self.send_device_status_query()

        except Exception as e:
            logger.error(f"Discover services error: {e}")

    def _retry_discover_services(self, retries_left: int):
        """重试发现服务，每次间隔1秒"""
        if retries_left <= 0:
            self.log("orange", "重试次数用尽，断开连接。请确保设备已配对：")
            self.log("orange", "  sudo bluetoothctl")
            self.log("orange", "  [bluetooth]# pair <设备MAC>")
            self.log("orange", "  [bluetooth]# trust <设备MAC>")
            self.disconnect_device()
            self.start_retry_timer()
            return

        def retry():
            if self.connected and not self.target_confirmed:
                self.log("blue", f"重试发现服务 (还剩 {retries_left - 1} 次)...")
                self.discover_services()

        QTimer.singleShot(1000, retry)

    def _subscribe_notify(self, char_path: str):
        try:
            char_iface = dbus.Interface(
                self.bus.get_object("org.bluez", char_path),
                "org.bluez.GattCharacteristic1"
            )
            char_iface.StartNotify(
                reply_handler=lambda: self.log("green", "通知已启用"),
                error_handler=lambda e: self.log("red", f"通知订阅失败: {e}")
            )
            # 注册特征值变化监听（监听该特征路径的 PropertiesChanged 信号）
            self.bus.add_signal_receiver(
                self.on_characteristic_changed,
                signal_name="PropertiesChanged",
                dbus_interface="org.freedesktop.DBus.Properties",
                path=char_path
            )
        except Exception as e:
            logger.error(f"Subscribe error: {e}")

    def on_properties_changed(self, interface: str, changed: dict, invalidated: list):
        if "Connected" in changed:
            connected = bool(changed["Connected"])
            if not connected and self.connected:
                self.connected = False
                self.log("red", f"Disconnected: {self.device_name}")
                self.disconnected_signal.emit()
                self.start_retry_timer()
        if "ServicesResolved" in changed:
            services_resolved = bool(changed["ServicesResolved"])
            if services_resolved and not self.target_confirmed:
                self.log("blue", "GATT 服务已发现")
                self.discover_services()

    def on_characteristic_changed(self, interface: str, changed: dict, invalidated: list):
        if "Value" in changed:
            data = bytes(changed["Value"])

            # 检查是否是设备状态
            if len(data) == 13 and data[0] == 0xAA and data[1] == 0xBB and data[2] == 0x00:
                battery = data[3]
                switch = data[9]
                self.status_update.emit(f"电量={battery} 开关={switch}")
                self.log("green", f"设备状态: 电量={battery} 开关={switch}")
            else:
                self.log("blue", f"Notify: {data.hex()}")

            # 转发给 TCP 客户端
            packet = build_packet(PacketType.BLE_NOTIFY, data)
            for client in self.clients:
                client.send(packet)

    def send_device_status_query(self):
        if self.write_char_path:
            try:
                char_iface = dbus.Interface(
                    self.bus.get_object("org.bluez", self.write_char_path),
                    "org.bluez.GattCharacteristic1"
                )
                char_iface.WriteValue(list(self.DEVICE_STATUS_QUERY), {},
                    reply_handler=lambda: None,
                    error_handler=lambda e: None)
                self.log("blue", "已发送设备状态查询指令")
            except Exception as e:
                logger.error(f"Query error: {e}")

    def send_ble_command(self, data: bytes):
        if self.write_char_path:
            try:
                char_iface = dbus.Interface(
                    self.bus.get_object("org.bluez", self.write_char_path),
                    "org.bluez.GattCharacteristic1"
                )
                char_iface.WriteValue(list(data), {},
                    reply_handler=lambda: None,
                    error_handler=lambda e: logger.error(f"Write error: {e}"))
            except Exception as e:
                logger.error(f"Send command error: {e}")

    def save_device_config(self):
        if self.device_name and self.device_path:
            try:
                props = dbus.Interface(
                    self.bus.get_object("org.bluez", self.device_path),
                    "org.freedesktop.DBus.Properties"
                )
                address = props.Get("org.bluez.Device1", "Address")
                self.config.ble_name = self.device_name
                self.config.ble_mac = str(address)
                self.config.save()
                self.log("blue", f"已保存设备: {self.device_name} [{address}]")
            except Exception as e:
                logger.error(f"Save config error: {e}")

    def start_retry_timer(self):
        # 8秒后重试
        asyncio.run_coroutine_threadsafe(self._retry_after_delay(), self.loop)

    async def _retry_after_delay(self):
        await asyncio.sleep(8)
        if not self.connected and self.running:
            self.log("gray", "重新扫描蓝牙设备...")
            self.scan_devices()

    def disconnect_device(self):
        self.connected = False
        self.target_confirmed = False
        if self.device_iface:
            try:
                self.device_iface.Disconnect()
            except Exception:
                pass

    def manual_connect(self, name: str, address: str):
        if self.connected:
            return
        self.auto_connecting = True
        for path, interfaces in self._get_all_objects().items():
            if "org.bluez.Device1" in interfaces:
                props = interfaces["org.bluez.Device1"]
                if props.get("Address", "") == address:
                    self.connect_to_device(path, name, address)
                    return
        self.log("red", f"未找到设备: {name}")

    def _get_all_objects(self):
        try:
            object_manager = dbus.Interface(
                self.bus.get_object("org.bluez", "/"),
                "org.freedesktop.DBus.ObjectManager"
            )
            return object_manager.GetManagedObjects()
        except:
            return {}

    async def start_tcp_server(self):
        try:
            self.server = await asyncio.start_server(
                self.handle_tcp_client,
                "0.0.0.0",
                self.config.server_port
            )
            self.log("darkcyan", f"TCP服务器已启动, 监听端口: {self.config.server_port}")
        except Exception as e:
            self.log("red", f"TCP服务器启动失败: {e}")

    async def handle_tcp_client(self, reader, writer):
        client = TcpClient(reader, writer, self)
        self.clients.append(client)
        self.client_count_changed.emit(len(self.clients))
        await client.handle()

    async def handle_packet(self, client: TcpClient, pkt_type: int, data: bytes):
        if pkt_type == PacketType.WRITE_COMMAND:
            self.send_ble_command(data)
        elif pkt_type == PacketType.WRITE_DATA:
            self.send_ble_command(data)
        elif pkt_type == PacketType.QUERY_BLE_STATUS:
            self.send_ble_status(client)
        elif pkt_type == PacketType.QUERY_DEVICE_INFO:
            self.send_device_info(client)

    def send_ble_status(self, client: TcpClient):
        status_data = bytes([
            1 if self.connected else 0,
            len(self.device_name.encode())
        ]) + self.device_name.encode() + bytes([
            len(self.config.ble_mac.encode())
        ]) + self.config.ble_mac.encode() + bytes([
            1 if self.target_confirmed else 0
        ])
        packet = build_packet(PacketType.BLE_STATUS_RESP, status_data)
        client.send(packet)

    def send_device_info(self, client: TcpClient):
        info = bytes([50, 0, 1, 0, 0, 0, 1, 0])
        packet = build_packet(PacketType.DEVICE_INFO_RESP, info)
        client.send(packet)

    def remove_client(self, client: TcpClient):
        if client in self.clients:
            self.clients.remove(client)
            self.client_count_changed.emit(len(self.clients))

    def stop(self):
        self.running = False
        self.disconnect_device()
        if self.server:
            self.server.close()


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.config = AppConfig.load()
        self.setWindowTitle("VibeCoding Keyboard BLE Driver")
        self.setMinimumSize(800, 500)

        # 创建系统托盘
        self.tray_icon = QSystemTrayIcon(self)
        self.tray_icon.setToolTip("BLE TCP Bridge")
        # 使用默认图标
        self.tray_icon.setIcon(self.style().standardIcon(
            self.style().SP_ComputerIcon))

        tray_menu = QMenu(self)
        show_action = QAction("显示窗口", self)
        show_action.triggered.connect(self.show_window)
        tray_menu.addAction(show_action)
        tray_menu.addSeparator()
        exit_action = QAction("退出程序", self)
        exit_action.triggered.connect(self.force_exit)
        tray_menu.addAction(exit_action)
        self.tray_icon.setContextMenu(tray_menu)
        self.tray_icon.activated.connect(self.on_tray_activated)
        self.tray_icon.show()

        self._setup_ui()
        self._start_worker()

        if self.config.start_minimized or "--minimized" in sys.argv:
            self.hide()
        else:
            self.show()

    def _setup_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)
        layout.setContentsMargins(15, 15, 15, 15)
        layout.setSpacing(10)

        # 顶部控制区
        top = QHBoxLayout()

        # 设备选择
        self.device_combo = QComboBox()
        self.device_combo.setMinimumWidth(180)
        self.device_combo.addItem("扫描中...")
        top.addWidget(QLabel("设备:"))
        top.addWidget(self.device_combo)

        # 连接按钮
        self.btn_connect = QPushButton("连接")
        self.btn_connect.setFixedWidth(80)
        self.btn_connect.clicked.connect(self.on_connect_clicked)
        top.addWidget(self.btn_connect)

        top.addStretch()

        # 状态信息
        info_layout = QVBoxLayout()
        self.label_device = QLabel("当前连接设备: 无")
        self.label_tcp = QLabel(f"TCP服务: {get_local_ip()}:{self.config.server_port} (客户端:0)")
        info_layout.addWidget(self.label_device)
        info_layout.addWidget(self.label_tcp)
        top.addLayout(info_layout)

        top.addStretch()

        # 退出按钮
        self.btn_exit = QPushButton("退出程序")
        self.btn_exit.setFixedWidth(90)
        self.btn_exit.clicked.connect(self.force_exit)
        top.addWidget(self.btn_exit)

        layout.addLayout(top)

        # 选项区
        options = QHBoxLayout()
        self.chk_minimize = QCheckBox("下次最小化启动")
        self.chk_minimize.setChecked(self.config.start_minimized)
        self.chk_minimize.stateChanged.connect(self.on_minimize_changed)
        options.addWidget(self.chk_minimize)
        layout.addLayout(options)

        # 日志区
        self.log_edit = QTextEdit()
        self.log_edit.setReadOnly(True)
        self.log_edit.setFont(QFont("Microsoft YaHei", 10))
        self.log_edit.setStyleSheet("background-color: #f5f5f5;")
        layout.addWidget(self.log_edit)

    def _start_worker(self):
        self.worker = AsyncWorker(self.config)
        self.worker.log_signal.connect(self.on_log)
        self.worker.device_found.connect(self.on_device_found)
        self.worker.connected_signal.connect(self.on_connected)
        self.worker.disconnected_signal.connect(self.on_disconnected)
        self.worker.status_update.connect(self.on_status_update)
        self.worker.client_count_changed.connect(self.on_client_count_changed)
        self.worker.start()

    def on_log(self, color: str, message: str):
        colors = {
            "red": "#CC0000", "blue": "#0000CC", "green": "#006600",
            "darkcyan": "#008B8B", "orange": "#FF8C00", "gray": "#808080"
        }
        hex_color = colors.get(color, "#000000")

        self.log_edit.append(
            f'<span style="color:{hex_color}">{message}</span>'
        )
        cursor = self.log_edit.textCursor()
        cursor.movePosition(QTextCursor.End)
        self.log_edit.setTextCursor(cursor)

    def on_device_found(self, name: str, address: str):
        # 检查是否已存在
        for i in range(self.device_combo.count()):
            if self.device_combo.itemData(i) == address:
                return

        if self.device_combo.count() == 1 and self.device_combo.itemText(0) == "扫描中...":
            self.device_combo.clear()

        self.device_combo.addItem(f"{name} [{address}]", address)

    def on_connect_clicked(self):
        idx = self.device_combo.currentIndex()
        if idx < 0:
            return
        address = self.device_combo.itemData(idx)
        name = self.device_combo.currentText().split("[")[0].strip()
        if address:
            self.worker.manual_connect(name, address)

    def on_connected(self, name: str):
        self.label_device.setText(f"当前连接设备: {name}")
        self.btn_connect.setEnabled(False)

    def on_disconnected(self):
        self.label_device.setText("当前连接设备: 无")
        self.btn_connect.setEnabled(True)

    def on_status_update(self, status: str):
        current = self.label_device.text()
        if "当前连接设备:" in current and current != "当前连接设备: 无":
            self.label_device.setText(f"{current} ({status})")

    def on_client_count_changed(self, count: int):
        self.label_tcp.setText(
            f"TCP服务: {get_local_ip()}:{self.config.server_port} (客户端:{count})"
        )

    def on_minimize_changed(self, state):
        self.config.start_minimized = bool(state)
        self.config.save()

    def on_tray_activated(self, reason):
        if reason == QSystemTrayIcon.Trigger:
            self.show_window()

    def show_window(self):
        self.showNormal()
        self.activateWindow()
        self.raise_()

    def closeEvent(self, event):
        # 关闭按钮最小化到托盘
        event.ignore()
        self.hide()
        self.tray_icon.showMessage(
            "BLE Bridge",
            "程序已最小化到系统托盘",
            QSystemTrayIcon.Information,
            2000
        )

    def force_exit(self):
        self.worker.stop()
        self.worker.wait(3000)
        self.tray_icon.hide()
        QApplication.instance().quit()


def main():
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    window = MainWindow()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()

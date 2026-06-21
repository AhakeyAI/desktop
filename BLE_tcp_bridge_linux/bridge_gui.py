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
LOG_FILE = Path("/tmp") / "ble_bridge.log"
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE, encoding='utf-8'),
        logging.StreamHandler()
    ]
)
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
        self.command_char_path: Optional[str] = None  # 0x7343 - Write Without Response
        self.data_char_path: Optional[str] = None     # 0x7341 - Write
        self.connected = False
        self.device_name = ""
        self.clients: List[TcpClient] = []
        self.running = False
        self.auto_connecting = False
        self.target_confirmed = False
        self.devices_map: Dict[str, str] = {}
        self.server = None
        self.claude_state: Optional[bytes] = None  # 保存 Claude 状态，用于重连后重发
        self.device_status: Dict[str, any] = {}    # 保存设备状态信息

        self.TARGET_SERVICE = "0000ffe0-0000-1000-8000-00805f9b34fb"
        self.DEVICE_STATUS_QUERY = bytes([0xAA, 0xBB, 0x00, 0xCC, 0xDD])

    def log(self, color: str, message: str):
        self.log_signal.emit(color, message)
        logger.info(f"[{color}] {message}")

    def run(self):
        # 必须在任何 dbus.SystemBus() 调用之前初始化 GLib mainloop
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        self.running = True

        # 启动 GLib mainloop 在单独线程中（用于 D-Bus 信号处理）
        import threading
        self.glib_thread = threading.Thread(target=self._run_glib_loop, daemon=True)
        self.glib_thread.start()

        try:
            self.loop.run_until_complete(self.main_loop())
        except Exception as e:
            logger.error(f"Worker error: {e}")
        finally:
            self.running = False
            self.loop.close()

    def _run_glib_loop(self):
        """GLib mainloop 运行在单独线程，用于处理 D-Bus 信号"""
        try:
            self.glib_loop = GLib.MainLoop()
            self.glib_loop.run()
        except Exception as e:
            logger.error(f"GLib loop error: {e}")

    async def main_loop(self):
        try:
            # 获取 D-Bus 总线连接
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

        # 调用 StartDiscovery() 主动扫描
        try:
            adapter_path = "/org/bluez/hci0"
            adapter = dbus.Interface(
                self.bus.get_object("org.bluez", adapter_path),
                "org.bluez.Adapter1"
            )
            adapter.StartDiscovery(
                reply_handler=lambda: self.log("blue", "开始 BLE 扫描..."),
                error_handler=lambda e: self.log("orange", f"扫描启动失败: {e}")
            )
        except Exception as e:
            self.log("orange", f"启动扫描异常: {e}")

        self.scan_devices()

        if self.config.has_saved_device:
            self.log("blue", f"目标设备: {self.config.ble_name} [{self.config.ble_mac}]")
            self.start_retry_timer()

    def stop_scan(self):
        """停止BLE扫描，避免干扰连接"""
        try:
            adapter_path = "/org/bluez/hci0"
            adapter = dbus.Interface(
                self.bus.get_object("org.bluez", adapter_path),
                "org.bluez.Adapter1"
            )
            adapter.StopDiscovery(
                reply_handler=lambda: self.log("blue", "BLE 扫描已停止"),
                error_handler=lambda e: self.log("orange", f"停止扫描失败: {e}")
            )
        except Exception as e:
            logger.error(f"Stop scan error: {e}")

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

            props_iface = dbus.Interface(
                self.bus.get_object("org.bluez", path),
                "org.freedesktop.DBus.Properties"
            )

            paired = bool(props_iface.Get("org.bluez.Device1", "Paired"))
            if not paired:
                self.log("orange", f"设备未配对，正在配对: {name}")
                self.device_iface.Pair(
                    reply_handler=lambda: self._on_pair_reply(path, name, address),
                    error_handler=lambda e: self._on_pair_error(e)
                )
                return

            self.log("blue", f"设备已配对，直接连接: {name}")

            self.bus.add_signal_receiver(
                self.on_properties_changed,
                signal_name="PropertiesChanged",
                dbus_interface="org.freedesktop.DBus.Properties",
                path=path
            )

            self.device_iface.Connect(
                reply_handler=lambda: self._on_connect_reply(),
                error_handler=lambda e: self._on_connect_error(e)
            )
        except Exception as e:
            self.log("red", f"连接失败: {e}")
            self.auto_connecting = False

    def _on_pair_reply(self, path: str, name: str, address: str):
        self.log("green", f"设备配对成功: {name}")
        self.connect_to_device(path, name, address)

    def _on_pair_error(self, error: str):
        self.log("red", f"设备配对失败: {error}")
        self.auto_connecting = False

    def _on_connect_reply(self):
        self.connected = True
        self.log("blue", f"Connected: {self.device_name}")
        self.connected_signal.emit(self.device_name)
        self.stop_scan()  # 连接成功后停止BLE扫描，避免干扰连接
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
        # 不自动重连！避免与BlueZ自动重连冲突

    def discover_services(self):
        try:
            object_manager = dbus.Interface(
                self.bus.get_object("org.bluez", "/"),
                "org.freedesktop.DBus.ObjectManager"
            )
            objects = object_manager.GetManagedObjects()

            services_found = []
            for path, interfaces in objects.items():
                if "org.bluez.GattService1" in interfaces:
                    props = interfaces["org.bluez.GattService1"]
                    uuid = props.get("UUID", "").lower()
                    services_found.append(f"{uuid}")

            self.log("blue", f"=== 已发现 {len(services_found)} 个 GATT 服务 ===")
            for i, svc in enumerate(services_found):
                is_target = " [目标]" if svc == self.TARGET_SERVICE.lower() else ""
                self.log("blue", f"  {i+1}. {svc}{is_target}")

            write_char_path = None
            notify_char_path = None
            command_char_path = None  # 0x7343 - Write Without Response (命令特征)
            data_char_path = None     # 0x7341 - Write (数据特征)

            self.log("blue", "=== 扫描所有特征 ===")
            for path, interfaces in objects.items():
                if "org.bluez.GattCharacteristic1" in interfaces:
                    char_props = interfaces["org.bluez.GattCharacteristic1"]
                    char_uuid = char_props.get("UUID", "").lower()
                    flags = char_props.get("Flags", [])

                    has_write = "write" in flags or "write-without-response" in flags
                    has_notify = "notify" in flags or "indicate" in flags
                    has_read = "read" in flags

                    if has_write and has_notify:
                        write_char_path = path
                        notify_char_path = path
                        self.log("green", f"  -> 找到 Write+Notify 特征: {char_uuid}")
                    elif has_write and not has_notify:
                        write_char_path = path
                        self.log("green", f"  -> 找到 Write 特征: {char_uuid}")
                    elif has_notify and not has_write:
                        notify_char_path = path
                        self.log("green", f"  -> 找到 Notify 特征: {char_uuid}")
                    elif has_read:
                        data_char_path = path
                        self.log("blue", f"  -> 找到 Read 特征: {char_uuid}")

            for path, interfaces in objects.items():
                if "org.bluez.GattCharacteristic1" in interfaces:
                    char_props = interfaces["org.bluez.GattCharacteristic1"]
                    char_uuid = char_props.get("UUID", "").lower()
                    flags = char_props.get("Flags", [])

                    has_write = "write" in flags or "write-without-response" in flags
                    has_notify = "notify" in flags or "indicate" in flags
                    has_read = "read" in flags

                    if char_uuid == "00007344-0000-1000-8000-00805f9b34fb":
                        notify_char_path = path
                        self.log("green", f"  -> 找到 AhaKey Notify 特征 [0x7344]: {char_uuid}")
                    elif char_uuid == "00007343-0000-1000-8000-00805f9b34fb":
                        command_char_path = path
                        self.log("green", f"  -> 找到 AhaKey Write 命令特征 [0x7343]: {char_uuid}")
                    elif char_uuid == "00007341-0000-1000-8000-00805f9b34fb":
                        data_char_path = path
                        self.log("green", f"  -> 找到 AhaKey Write 数据特征 [0x7341]: {char_uuid}")

            # 如果没有找到专用的0x7343/0x7341，则使用通用Write特征
            if not command_char_path and write_char_path:
                command_char_path = write_char_path
            if not data_char_path and write_char_path:
                data_char_path = write_char_path

            self.write_char_path = command_char_path  # 默认使用命令特征
            self.notify_char_path = notify_char_path
            self.command_char_path = command_char_path  # 0x7343 - Write Without Response
            self.data_char_path = data_char_path        # 0x7341 - Write

            self.log("blue", f"=== 特征查找结果 ===")
            self.log("blue", f"  命令特征路径 [0x7343]: {command_char_path}")
            self.log("blue", f"  数据特征路径 [0x7341]: {data_char_path}")
            self.log("blue", f"  Notify特征路径: {notify_char_path}")

            if not command_char_path:
                self.log("orange", "未找到命令特征 [0x7343]，重试中...")
                self._retry_discover_services(3)
                return

            if not notify_char_path:
                self.log("orange", "未找到 Notify 特征，重试中...")
                self._retry_discover_services(3)
                return

            self.log("blue", "发现目标服务")

            if self.notify_char_path:
                self._subscribe_notify(self.notify_char_path)

            if self.write_char_path and self.notify_char_path:
                self.target_confirmed = True
                self.save_device_config()
                # 状态查询会在 _subscribe_notify 的回调中发送

        except Exception as e:
            logger.error(f"Discover services error: {e}")

    def _on_connected_delayed(self):
        """连接后的延迟操作 - 在 StartNotify 成功后被调用"""
        # 延迟500ms发送状态查询，确保BlueZ完成所有GATT操作
        QTimer.singleShot(500, self._send_initial_status_query)

        # 启动保活定时器，每30秒发送一次心跳防止设备休眠
        self.start_keepalive_timer()

        # 重连后重发保存的 Claude 状态到 BLE 设备
        if self.claude_state:
            self.log("blue", f"重发 Claude 状态到设备: {self.claude_state.hex()}")
            QTimer.singleShot(600, lambda: self.send_ble_command(self.claude_state, char_path=self.command_char_path, max_chunk=20))

    def _send_initial_status_query(self):
        """发送初始状态查询"""
        self.log("blue", "发送初始状态查询...")
        self.send_device_status_query()

    def _retry_discover_services(self, retries_left: int):
        """重试发现服务，每次间隔1秒"""
        if retries_left <= 0:
            self.log("orange", "重试次数用尽，请手动重新连接设备")
            self.disconnect_device()
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
            # 在 StartNotify 成功后再发送状态查询
            def on_notify_started():
                self.log("green", "通知已启用")
                self._on_connected_delayed()

            char_iface.StartNotify(
                reply_handler=on_notify_started,
                error_handler=lambda e: self.log("red", f"通知订阅失败: {e}")
            )
            # 注册特征值变化监听（监听该特征路径的 PropertiesChanged 信号）
            self.bus.add_signal_receiver(
                self.on_characteristic_changed,
                signal_name="PropertiesChanged",
                dbus_interface="org.freedesktop.DBus.Properties",
                path=char_path
            )
            self.log("blue", f"已订阅特征通知: {char_path}")
        except Exception as e:
            logger.error(f"Subscribe error: {e}")

    def on_properties_changed(self, interface: str, changed: dict, invalidated: list):
        if "Connected" in changed:
            connected = bool(changed["Connected"])
            if not connected and self.connected:
                self.connected = False
                self.log("red", f"Disconnected: {self.device_name}")
                self.disconnected_signal.emit()
                # 不自动重连！避免与BlueZ自动重连冲突导致设备断开
                # 如需重连，请在UI上手动点击连接按钮
        if "ServicesResolved" in changed:
            services_resolved = bool(changed["ServicesResolved"])
            if services_resolved and not self.target_confirmed:
                self.log("blue", "GATT 服务已发现")
                self.discover_services()

    def on_characteristic_changed(self, interface: str, changed: dict, invalidated: list):
        if "Value" in changed:
            data = bytes(changed["Value"])
            self.log("blue", f"收到 BLE 数据: 长度={len(data)}, 原始数据={data.hex()}")

            # 检查是否是设备状态（格式: [0xAA][0xBB][0x00][8字节设备信息][0xCC][0xDD] = 13字节）
            if len(data) == 13 and data[0] == 0xAA and data[1] == 0xBB and data[2] == 0x00 and data[11] == 0xCC and data[12] == 0xDD:
                battery = data[3]
                signal = data[4]
                firmware = f"{data[5]}.{data[6]}"
                # 保存设备状态，对标 Windows 版 Protocol.cs 格式
                self.device_status = {
                    "battery": battery,
                    "signal": signal,
                    "firmware": firmware,
                    "work_mode": data[7] if len(data) > 7 else 0,
                    "light_mode": data[8] if len(data) > 8 else 0,
                    "switch_state": data[9] if len(data) > 9 else 0
                }
                self.status_update.emit(f"电量={battery}%")
                self.log("green", f"设备状态: 电量={battery}% 信号={signal} 固件={firmware}")
                # 设备状态包不转发给 TCP 客户端
                return
            
            # 检查是否是 Claude 状态（0xAA BB 90 ...）
            if len(data) >= 3 and data[0] == 0xAA and data[1] == 0xBB and data[2] == 0x90:
                self.claude_state = data  # 保存 Claude 状态
                self.log("green", f"Claude 状态已保存: {data.hex()}")
            
            # 转发给 TCP 客户端（除了设备状态之外的所有数据）
            packet = build_packet(PacketType.BLE_NOTIFY, data)
            for client in self.clients:
                client.send(packet)

    def start_keepalive_timer(self):
        """启动保活定时器，每30秒发送心跳防止设备休眠"""
        self.stop_keepalive_timer()
        self.keepalive_timer = QTimer()
        self.keepalive_timer.timeout.connect(self._keepalive_ping)
        self.keepalive_timer.start(30000)  # 30秒
        self.log("blue", "保活定时器已启动")

    def stop_keepalive_timer(self):
        """停止保活定时器"""
        if hasattr(self, 'keepalive_timer') and self.keepalive_timer:
            self.keepalive_timer.stop()
            self.keepalive_timer = None

    def _keepalive_ping(self):
        """保活心跳：只发送状态查询，不触发重连"""
        if not self.connected or not self.write_char_path:
            return

        # 连接正常，发送保活心跳
        self.log("blue", "保活心跳...")
        self.send_device_status_query()
        # 注意：不要在这里触发重连！BLE扫描会干扰现有连接

    def send_device_status_query(self):
        """发送状态查询，返回是否成功"""
        if not self.write_char_path:
            return False

        try:
            char_iface = dbus.Interface(
                self.bus.get_object("org.bluez", self.write_char_path),
                "org.bluez.GattCharacteristic1"
            )
            self.log("blue", f"发送状态查询到: {self.write_char_path}")
            self.log("blue", f"查询命令: {self.DEVICE_STATUS_QUERY.hex()}")

            success = [False]  # 使用列表来在回调中修改值

            def on_success():
                success[0] = True
                self.log("green", "状态查询已发送，等待设备回复")

            def on_error(e):
                success[0] = False
                self.log("red", f"状态查询发送失败: {e}")

            char_iface.WriteValue(list(self.DEVICE_STATUS_QUERY), {},
                reply_handler=on_success,
                error_handler=on_error)

            return success[0]

        except Exception as e:
            logger.error(f"Query error: {e}")
            self.log("red", f"状态查询异常: {e}")
            return False

    def send_ble_command(self, data: bytes, char_path: str = None, max_chunk: int = 20):
        """发送 BLE 命令，支持分片
        
        Args:
            data: 要发送的数据
            char_path: 特征路径，默认使用 write_char_path
            max_chunk: 每包最大字节数，默认20（BLE MTU）
        """
        target_path = char_path or self.write_char_path
        if not target_path:
            self.log("orange", "无可用的写入特征路径")
            return

        try:
            char_iface = dbus.Interface(
                self.bus.get_object("org.bluez", target_path),
                "org.bluez.GattCharacteristic1"
            )
            
            # 如果数据超过 max_chunk，进行分片
            if len(data) <= max_chunk:
                char_iface.WriteValue(list(data), {},
                    reply_handler=lambda: None,
                    error_handler=lambda e: logger.error(f"Write error: {e}"))
                self.log("blue", f"BLE发送: {data.hex()}")
            else:
                # 分片发送
                chunks = [data[i:i + max_chunk] for i in range(0, len(data), max_chunk)]
                total = len(chunks)
                for i, chunk in enumerate(chunks, 1):
                    char_iface.WriteValue(list(chunk), {},
                        reply_handler=lambda: None,
                        error_handler=lambda e: logger.error(f"Write error: {e}"))
                    self.log("blue", f"BLE发送: {chunk.hex()} ({i}/{total})")
                    # BlueZ 有自己的 GATT 写入队列，无需额外延迟
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
        self.write_char_path = None
        self.notify_char_path = None
        self.command_char_path = None
        self.data_char_path = None
        self.stop_keepalive_timer()  # 停止保活定时器

        if self.device_iface:
            try:
                self.log("blue", f"正在断开设备连接: {self.device_path}")
                self.device_iface.Disconnect()
                self.log("blue", "BLE 设备连接已断开")
            except Exception as e:
                self.log("red", f"断开失败: {e}")

        self.disconnected_signal.emit()

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
            # 捕获 Claude 状态（0xAA BB 90 ...）
            if len(data) >= 3 and data[0] == 0xAA and data[1] == 0xBB and data[2] == 0x90:
                self.claude_state = data
                self.log("blue", f"捕获 Claude 状态: {data.hex()}")
            # 命令写入 0x7343，每包最大 20 字节（BLE MTU）
            self.send_ble_command(data, char_path=self.command_char_path, max_chunk=20)
        elif pkt_type == PacketType.WRITE_DATA:
            # 数据写入 0x7341，每包最大 200 字节
            self.send_ble_command(data, char_path=self.data_char_path, max_chunk=200)
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
        # 返回真实设备状态信息，对标 Windows 版 Protocol.cs 格式
        battery = self.device_status.get("battery", 0)
        signal = self.device_status.get("signal", 0)
        firmware = self.device_status.get("firmware", "0.0")
        work_mode = self.device_status.get("work_mode", 0)
        light_mode = self.device_status.get("light_mode", 0)
        switch_state = self.device_status.get("switch_state", 0)
        
        # 解析固件版本
        fw_parts = firmware.split(".")
        fw_major = int(fw_parts[0]) if fw_parts else 0
        fw_minor = int(fw_parts[1]) if len(fw_parts) > 1 else 0
        
        info = bytes([
            battery,      # data[0] 电量
            signal,       # data[1] 信号
            fw_major,     # data[2] 固件主版本
            fw_minor,     # data[3] 固件次版本
            work_mode,    # data[4] 工作模式
            light_mode,   # data[5] 灯光模式
            switch_state, # data[6] 开关状态
            0            # data[7] Reserve
        ])
        packet = build_packet(PacketType.DEVICE_INFO_RESP, info)
        client.send(packet)
        self.log("blue", f"发送设备信息: 电量={battery}% 信号={signal} 固件={firmware}")

    def remove_client(self, client: TcpClient):
        if client in self.clients:
            self.clients.remove(client)
            self.client_count_changed.emit(len(self.clients))

    def stop(self):
        self.running = False
        # 退出时保持BLE连接不断开，让设备继续连接到电脑蓝牙
        self.log("blue", "程序正在退出，保持BLE设备连接...")
        if self.server:
            self.server.close()
        # 优雅退出 GLib mainloop
        if hasattr(self, 'glib_loop') and self.glib_loop.is_running():
            self.glib_loop.quit()
        self.log("blue", "BLE Bridge 程序已停止（设备保持连接）")


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

        if name and name.startswith("AhaKey"):
            self.device_combo.addItem(f"{name} [{address}]", address)

    def on_connect_clicked(self):
        if self.btn_connect.text() == "断开":
            # 断开BLE连接并清理状态
            self.worker.disconnect_device()
            return

        idx = self.device_combo.currentIndex()
        if idx < 0:
            return
        address = self.device_combo.itemData(idx)
        name = self.device_combo.currentText().split("[")[0].strip()
        if address:
            self.worker.manual_connect(name, address)

    def on_connected(self, name: str):
        self._connected_device_name = name  # 记录原始设备名
        self.label_device.setText(f"当前连接设备: {name}")
        self.btn_connect.setText("断开")
        self.btn_connect.setEnabled(True)

    def on_disconnected(self):
        self.label_device.setText("当前连接设备: 无")
        self.btn_connect.setText("连接")
        self.btn_connect.setEnabled(True)

    def on_status_update(self, status: str):
        name = getattr(self, '_connected_device_name', '')
        if name:
            self.label_device.setText(f"当前连接设备: {name} ({status})")

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

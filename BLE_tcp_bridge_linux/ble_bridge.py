#!/usr/bin/env python3
"""
BLE TCP Bridge for Linux
使用 BlueZ D-Bus API 连接 BLE 设备，提供 TCP 接口给上位机

依赖:
    pip install dbus-python pydbus

运行:
    python ble_bridge.py
"""

import asyncio
import sys
import os
import struct
import logging
import signal
import argparse
from typing import Optional, List
from dataclasses import dataclass
from enum import IntEnum

import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class PacketType(IntEnum):
    """TCP 通信协议包类型"""
    WRITE_DATA = 0x01
    WRITE_COMMAND = 0x02
    QUERY_BLE_STATUS = 0x03
    QUERY_DEVICE_INFO = 0x04
    BLE_NOTIFY = 0x81
    BLE_STATUS_RESP = 0x82
    DEVICE_INFO_RESP = 0x83


@dataclass
class BleStatusInfo:
    connected: bool = False
    device_name: str = ""
    mac_address: str = ""
    is_target_device: bool = False


@dataclass
class DeviceStatusInfo:
    battery_level: int = 0
    signal_strength: int = 0
    firmware_main: int = 0
    firmware_sub: int = 0
    work_mode: int = 0
    light_mode: int = 0
    switch_state: int = 0
    reserve: int = 0


def build_packet(pkt_type: PacketType, data: bytes = None) -> bytes:
    """构建协议包: [Type:1][Length:2 LE][Data:N]"""
    length = len(data) if data else 0
    header = bytes([pkt_type, length & 0xFF, (length >> 8) & 0xFF])
    return header + (data if data else b'')


def build_ble_status_packet(status: BleStatusInfo) -> bytes:
    """构建BLE状态响应包"""
    name_bytes = status.device_name.encode('utf-8')
    mac_bytes = status.mac_address.encode('utf-8')
    data = bytes([
        1 if status.connected else 0,
        len(name_bytes)
    ]) + name_bytes + bytes([
        len(mac_bytes)
    ]) + mac_bytes + bytes([
        1 if status.is_target_device else 0
    ])
    return build_packet(PacketType.BLE_STATUS_RESP, data)


def build_device_info_packet(info: DeviceStatusInfo) -> bytes:
    """构建设备状态信息响应包"""
    data = bytes([
        info.battery_level,
        info.signal_strength,
        info.firmware_main,
        info.firmware_sub,
        info.work_mode,
        info.light_mode,
        info.switch_state,
        info.reserve
    ])
    return build_packet(PacketType.DEVICE_INFO_RESP, data)


def is_device_status_notification(data: bytes) -> bool:
    """检查是否为设备状态信息包 [0xAA][0xBB][0x00]...[0xCC][0xDD]"""
    if len(data) != 13:
        return False
    return data[0] == 0xAA and data[1] == 0xBB and data[2] == 0x00 \
        and data[11] == 0xCC and data[12] == 0xDD


def parse_device_status(data: bytes) -> DeviceStatusInfo:
    """从通知数据中解析设备状态"""
    info = DeviceStatusInfo()
    if len(data) >= 12:
        info.battery_level = data[3]
        info.signal_strength = data[4]
        info.firmware_main = data[5]
        info.firmware_sub = data[6]
        info.work_mode = data[7]
        info.light_mode = data[8]
        info.switch_state = data[9]
    return info


class TcpClient:
    """TCP 客户端连接"""
    def __init__(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter, bridge: 'BleBridge'):
        self.reader = reader
        self.writer = writer
        self.bridge = bridge
        self.addr = writer.get_extra_info('peername')
        logger.info(f"TCP client connected: {self.addr}")

    async def handle(self):
        """处理客户端数据"""
        try:
            while True:
                # 读取包头 (3 字节)
                header = await self.reader.readexactly(3)
                pkt_type = header[0]
                length = header[1] | (header[2] << 8)

                # 读取数据包
                data = b''
                if length > 0:
                    data = await self.reader.readexactly(length)

                await self.bridge.handle_packet(self, pkt_type, data)
        except asyncio.IncompleteReadError:
            logger.info(f"TCP client disconnected: {self.addr}")
        except Exception as e:
            logger.error(f"TCP client error: {self.addr}, {e}")
        finally:
            self.bridge.remove_client(self)

    def send(self, data: bytes):
        """发送数据到客户端"""
        try:
            self.writer.write(data)
            # asyncio StreamWriter 没有 flush 参数
        except Exception as e:
            logger.error(f"Send to {self.addr} failed: {e}")


class BleBridge:
    """BLE 桥接器 - 连接 BlueZ 和 TCP"""

    # AhaKey 设备的 BLE 服务和特征 UUID
    TARGET_SERVICE_UUID = "0000ffe0-0000-1000-8000-00805f9b34fb"
    WRITE_CHAR_UUID = "0000ffe1-0000-1000-8000-00805f9b34fb"
    NOTIFY_CHAR_UUID = "0000ffe1-0000-1000-8000-00805f9b34fb"  # 相同 UUID，0x7341/0x7343/0x7344 是设备的 handle

    # 设备的 MAC 地址 (需要替换为实际设备地址)
    DEFAULT_DEVICE_MAC = "00:00:00:00:00:00"

    def __init__(self, device_mac: str = None, target_uuid: str = None):
        self.device_mac = device_mac or os.environ.get("AHAKEY_BLE_MAC", self.DEFAULT_DEVICE_MAC)
        self.target_uuid = target_uuid or os.environ.get("AHAKEY_BLE_UUID", self.TARGET_SERVICE_UUID)
        self.bus: Optional[dbus.Bus] = None
        self.device_path: Optional[str] = None
        self.device_props: Optional[dbus.proxies.Interface] = None
        self.device_iface: Optional[dbus.proxies.Interface] = None
        self.notify_char_path: Optional[str] = None
        self.write_char_path: Optional[str] = None

        self.connected = False
        self.device_name = "Unknown"
        self.clients: List[TcpClient] = []
        self.device_status = DeviceStatusInfo()

        # 设备状态查询命令
        self.DEVICE_STATUS_QUERY = bytes([0xAA, 0xBB, 0x00, 0xCC, 0xDD])

    async def start(self):
        """启动 BLE 桥接"""
        logger.info(f"Starting BLE Bridge for device: {self.device_mac}")
        await self.connect_bluetooth()
        await self.start_tcp_server()

    async def connect_bluetooth(self):
        """连接到 BLE 设备"""
        logger.info("Connecting to Bluetooth...")
        try:
            dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
            self.bus = dbus.SystemBus()

            # 获取 BlueZ Adapter
            adapter_path = await self.get_adapter_path()
            logger.info(f"Using adapter: {adapter_path}")

            # 获取设备路径
            self.device_path = f"{adapter_path}/dev_{self.device_mac.replace(':', '_')}"
            
            # 检查设备是否已知
            try:
                self.device_props = self.bus.get_object("org.bluez", self.device_path)
            except dbus.exceptions.DBusException:
                logger.warning(f"Device {self.device_mac} not found. Make sure it's paired and powered on.")
                # 不阻塞，继续启动 TCP 服务器
                return

            # 获取设备接口
            self.device_iface = dbus.Interface(
                self.bus.get_object("org.bluez", self.device_path),
                "org.bluez.Device1"
            )

            # 监听属性变化
            self.bus.add_signal_receiver(
                self.on_properties_changed,
                signal_name="PropertiesChanged",
                path=self.device_path,
                interface_keyword="org.bluez.Device1"
            )

            # 连接设备
            logger.info(f"Connecting to device {self.device_mac}...")
            self.device_iface.Connect(reply_handler=self._on_connect_reply, error_handler=self._on_connect_error)
            
        except Exception as e:
            logger.error(f"BLE connection error: {e}")
            import traceback
            traceback.print_exc()

    def _on_connect_reply(self):
        """连接成功回调"""
        logger.info("BLE device connected")
        self.connected = True
        # 获取服务
        self._discover_services()

    def _on_connect_error(self, error: dbus.DBusException):
        """连接失败回调"""
        logger.error(f"BLE connect failed: {error}")

    def _discover_services(self):
        """发现服务"""
        try:
            # 获取 GATT 服务
            object_manager = dbus.Interface(
                self.bus.get_object("org.bluez", "/"),
                "org.freedesktop.DBus.ObjectManager"
            )
            objects = object_manager.GetManagedObjects()
            
            for path, interfaces in objects.items():
                if "org.bluez.GattService1" in interfaces:
                    props = interfaces["org.bluez.GattService1"]
                    if props.get("UUID") == self.target_uuid:
                        logger.info(f"Found target service: {path}")
                        # 查找特征
                        for char_path, char_interfaces in objects.items():
                            if char_path.startswith(path):
                                if "org.bluez.GattCharacteristic1" in char_interfaces:
                                    char_props = char_interfaces["org.bluez.GattCharacteristic1"]
                                    char_uuid = char_props.get("UUID", "")
                                    flags = char_props.get("Flags", [])
                                    logger.info(f"  Characteristic: {char_uuid}, flags: {flags}")
                                    
                                    # 根据 UUID 判断是读/写/通知特征
                                    if "write" in flags or "write-without-response" in flags:
                                        self.write_char_path = char_path
                                        logger.info(f"    -> Write characteristic")
                                    if "notify" in flags or "indicate" in flags:
                                        self.notify_char_path = char_path
                                        logger.info(f"    -> Notify characteristic")
                                        self._subscribe_notify(char_path)

            # 查询设备状态
            if self.write_char_path:
                self._query_device_status()

        except Exception as e:
            logger.error(f"Service discovery error: {e}")

    def _subscribe_notify(self, char_path: str):
        """订阅通知"""
        try:
            char_iface = dbus.Interface(
                self.bus.get_object("org.bluez", char_path),
                "org.bluez.GattCharacteristic1"
            )
            char_iface.StartNotify(
                reply_handler=lambda: logger.info("Notify started"),
                error_handler=lambda e: logger.error(f"Notify error: {e}")
            )
            
            # 监听 ValueChanged 信号
            self.bus.add_signal_receiver(
                self.on_characteristic_changed,
                signal_name="PropertiesChanged",
                path=char_path,
                interface_keyword="org.bluez.GattCharacteristic1"
            )
            logger.info(f"Subscribed to notifications on {char_path}")
        except Exception as e:
            logger.error(f"Subscribe notify error: {e}")

    def on_characteristic_changed(self, interface: str, changed: dict, invalidated: list):
        """特征值变化回调"""
        if "Value" in changed:
            data = bytes(changed["Value"])
            logger.debug(f"Notification: {data.hex()}")
            
            # 检查是否是设备状态
            if is_device_status_notification(data):
                self.device_status = parse_device_status(data)
                logger.info(f"Device status: battery={self.device_status.battery_level}, "
                          f"switch={self.device_status.switch_state}")
            
            # 转发给所有 TCP 客户端
            packet = build_packet(PacketType.BLE_NOTIFY, data)
            for client in self.clients:
                client.send(packet)

    def on_properties_changed(self, interface: str, changed: dict, invalidated: list):
        """设备属性变化"""
        if "Connected" in changed:
            self.connected = changed["Connected"]
            logger.info(f"Device connected: {self.connected}")
        if "Name" in changed:
            self.device_name = str(changed["Name"])
            logger.info(f"Device name: {self.device_name}")

    def _query_device_status(self):
        """查询设备状态"""
        if self.write_char_path:
            try:
                char_iface = dbus.Interface(
                    self.bus.get_object("org.bluez", self.write_char_path),
                    "org.bluez.GattCharacteristic1"
                )
                char_iface.WriteValue(self.DEVICE_STATUS_QUERY, {},
                    reply_handler=lambda: logger.debug("Device status query sent"),
                    error_handler=lambda e: logger.error(f"Write error: {e}")
                )
            except Exception as e:
                logger.error(f"Query device status error: {e}")

    async def get_adapter_path(self) -> str:
        """获取 BlueZ 适配器路径"""
        object_manager = dbus.Interface(
            self.bus.get_object("org.bluez", "/"),
            "org.freedesktop.DBus.ObjectManager"
        )
        objects = object_manager.GetManagedObjects()
        
        for path, interfaces in objects.items():
            if "org.bluez.Adapter1" in interfaces:
                return path
        raise RuntimeError("No Bluetooth adapter found")

    async def start_tcp_server(self, host: str = "127.0.0.1", port: int = 9000):
        """启动 TCP 服务器"""
        server = await asyncio.start_server(self.handle_tcp_client, host, port)
        logger.info(f"TCP server listening on {host}:{port}")
        
        async with server:
            await server.serve_forever()

    async def handle_tcp_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """处理 TCP 客户端连接"""
        client = TcpClient(reader, writer, self)
        self.clients.append(client)
        await client.handle()

    async def handle_packet(self, client: TcpClient, pkt_type: int, data: bytes):
        """处理来自 TCP 客户端的包"""
        logger.debug(f"Received packet: type=0x{pkt_type:02x}, len={len(data)}")
        
        try:
            pkt_type = PacketType(pkt_type)
        except ValueError:
            logger.warning(f"Unknown packet type: 0x{pkt_type:02x}")
            return

        if pkt_type == PacketType.WRITE_COMMAND:
            await self.write_command(data)
        elif pkt_type == PacketType.WRITE_DATA:
            await self.write_data(data)
        elif pkt_type == PacketType.QUERY_BLE_STATUS:
            self.send_ble_status(client)
        elif pkt_type == PacketType.QUERY_DEVICE_INFO:
            self.send_device_info(client)

    async def write_command(self, data: bytes):
        """写命令到 BLE 设备"""
        if not self.write_char_path:
            logger.warn("Write char not available")
            return
        try:
            char_iface = dbus.Interface(
                self.bus.get_object("org.bluez", self.write_char_path),
                "org.bluez.GattCharacteristic1"
            )
            char_iface.WriteValue(list(data), {},
                reply_handler=lambda: logger.debug("Command sent"),
                error_handler=lambda e: logger.error(f"Write error: {e}")
            )
        except Exception as e:
            logger.error(f"Write command error: {e}")

    async def write_data(self, data: bytes):
        """写数据到 BLE 设备"""
        await self.write_command(data)

    def send_ble_status(self, client: TcpClient):
        """发送 BLE 状态到客户端"""
        status = BleStatusInfo(
            connected=self.connected,
            device_name=self.device_name,
            mac_address=self.device_mac,
            is_target_device=self.connected
        )
        packet = build_ble_status_packet(status)
        client.send(packet)

    def send_device_info(self, client: TcpClient):
        """发送设备信息到客户端"""
        packet = build_device_info_packet(self.device_status)
        client.send(packet)

    def remove_client(self, client: TcpClient):
        """移除客户端"""
        if client in self.clients:
            self.clients.remove(client)

    def disconnect(self):
        """断开 BLE 连接"""
        if self.device_iface and self.connected:
            try:
                self.device_iface.Disconnect()
            except Exception as e:
                logger.error(f"Disconnect error: {e}")


async def list_devices():
    """列出所有可用的 BLE 设备"""
    logger.info("Scanning for BLE devices...")
    try:
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        bus = dbus.SystemBus()

        object_manager = dbus.Interface(
            bus.get_object("org.bluez", "/"),
            "org.freedesktop.DBus.ObjectManager"
        )
        objects = object_manager.GetManagedObjects()

        found_devices = []
        for path, interfaces in objects.items():
            if "org.bluez.Device1" in interfaces:
                props = interfaces["org.bluez.Device1"]
                name = props.get("Name", "Unknown")
                address = props.get("Address", "Unknown")
                connected = props.get("Connected", False)
                paired = props.get("Paired", False)
                trusted = props.get("Trusted", False)

                if paired or trusted:
                    found_devices.append({
                        "name": name,
                        "address": address,
                        "connected": connected,
                        "path": path
                    })
                    logger.info(f"  [{'+' if connected else ' '}] {address} - {name}")

        if not found_devices:
            logger.info("No paired devices found. Pair with bluetoothctl first:")
            logger.info("  sudo bluetoothctl")
            logger.info("  [bluetooth]# scan on")
            logger.info("  [bluetooth]# pair <device-mac>")
            logger.info("  [bluetooth]# trust <device-mac>")

    except Exception as e:
        logger.error(f"List devices error: {e}")
        import traceback
        traceback.print_exc()


async def main():
    parser = argparse.ArgumentParser(description="BLE TCP Bridge for Linux")
    parser.add_argument("--mac", type=str, help="Device MAC address (e.g., AA:BB:CC:DD:EE:FF)")
    parser.add_argument("--port", type=int, default=9000, help="TCP server port (default: 9000)")
    parser.add_argument("--list", action="store_true", help="List paired BLE devices and exit")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging")
    args = parser.parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    if args.list:
        await list_devices()
        return

    bridge = BleBridge(device_mac=args.mac)

    # 信号处理
    loop = asyncio.get_event_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, bridge.disconnect)

    await bridge.start()


if __name__ == "__main__":
    asyncio.run(main())

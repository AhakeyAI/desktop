"""
设备服务层 — 高级设备命令操作
基于 TcpClient 实现命令/响应模式和大数据传输
"""

import struct
import threading

from PySide6.QtCore import QObject, Signal, Slot, Qt

from .protocol import (
    PKT_WRITE_CMD, PKT_WRITE_DATA, PKT_BLE_NOTIFY,
    PKT_QUERY_STATUS, PKT_QUERY_INFO, PKT_STATUS_RESP, PKT_INFO_RESP,
    DeviceCmd, KeySubType, build_device_frame, parse_device_frame,
    parse_status_response, parse_info_response, parse_pic_state_response,
)
from .tcp_client import TcpClient


class DeviceService(QObject):
    """设备命令服务，提供同步命令接口和异步进度通知"""

    MAX_CHUNK = 4096

    upload_progress = Signal(int, int)     # bytes_sent, total_bytes
    status_received = Signal(dict)         # BLE status info
    info_received = Signal(dict)           # device info

    def __init__(self, tcp_client: TcpClient, parent=None):
        super().__init__(parent)
        self.tcp = tcp_client

        self._lock = threading.Lock()
        self._resp_event = threading.Event()
        self._resp_type = None
        self._resp_payload = None

        # DirectConnection: _on_packet 在 TCP 接收线程中直接执行,
        # 避免 send_command 阻塞主线程时信号排队导致死锁
        self.tcp.packet_received.connect(self._on_packet, Qt.DirectConnection)

    @Slot(object)
    def _on_packet(self, packet):
        """处理收到的 TCP 包"""
        pkt_type, data = packet
        if pkt_type == PKT_BLE_NOTIFY:
            parsed = parse_device_frame(data)
            if not parsed:
                return
            cmd_type, payload = parsed
            self._resp_type = cmd_type
            self._resp_payload = payload
            self._resp_event.set()

        elif pkt_type == PKT_STATUS_RESP:
            info = parse_status_response(data)
            self.status_received.emit(info)

        elif pkt_type == PKT_INFO_RESP:
            info = parse_info_response(data)
            self.info_received.emit(info)

    def _wait_response(self, expect_type: int, timeout: float = 5.0) -> bytes:
        """等待指定类型的设备响应"""
        if not self._resp_event.wait(timeout):
            raise TimeoutError(f"Wait response 0x{expect_type:02X} timeout")
        if self._resp_type != expect_type:
            raise RuntimeError(
                f"Unexpected response: 0x{self._resp_type:02X}, "
                f"expected: 0x{expect_type:02X}"
            )
        return self._resp_payload

    # ==============================
    # 普通命令
    # ==============================

    def send_command(self, cmd: DeviceCmd, data: bytes = b"", timeout: float = 5.0) -> bool:
        """发送命令并等待确认"""
        with self._lock:
            frame = build_device_frame(cmd, data)
            self._resp_event.clear()
            self.tcp.send(PKT_WRITE_CMD, frame)
            payload = self._wait_response(cmd, timeout)
            if not payload or payload[0] != 0:
                raise RuntimeError(f"Device error, cmd=0x{cmd:02X}, code={payload}")
            return True

    def query_status(self):
        """查询 BLE 连接状态"""
        self.tcp.send(PKT_QUERY_STATUS)

    def query_info(self):
        """查询设备信息"""
        self.tcp.send(PKT_QUERY_INFO)

    def save_config(self):
        """保存配置到设备"""
        self.send_command(DeviceCmd.SAVE_CONFIG)

    # ==============================
    # 大批量数据写入
    # ==============================

    def write_large_data(self, address: int, data: bytes, timeout: float = 5.0):
        """分块写入大量数据到设备"""
        if address % 4096 != 0:
            raise ValueError("Address must be 4K aligned")

        total_len = len(data)
        offset = 0

        with self._lock:
            while offset < total_len:
                chunk = data[offset:offset + self.MAX_CHUNK]
                chunk_len = len(chunk)
                current_addr = address + offset

                # 1. PREPARE_WRITE
                cmd_data = struct.pack("<BHI", 0, chunk_len, current_addr)
                self._resp_event.clear()
                self.tcp.send(PKT_WRITE_CMD, build_device_frame(DeviceCmd.PREPARE_WRITE, cmd_data))
                payload = self._wait_response(DeviceCmd.PREPARE_WRITE, timeout)
                if not payload or payload[0] != 0:
                    raise RuntimeError(f"Prepare write failed at offset {offset}")

                # 2. 发送数据块
                self._resp_event.clear()
                self.tcp.send(PKT_WRITE_DATA, chunk)
                payload = self._wait_response(DeviceCmd.WRITE_RESULT, timeout)
                if not payload or payload[0] != 0:
                    raise RuntimeError(f"Write chunk failed at offset {offset}")

                offset += chunk_len
                self.upload_progress.emit(offset, total_len)

        return True

    # ==============================
    # 图片更新
    # ==============================

    # ==============================
    # 自定义按键
    # ==============================

    def update_custom_key(self, mode: int, key_index: int, sub_type: int, data: bytes):
        """发送自定义按键配置到设备
        sub_type: KeySubType.SHORTCUT / MACRO / DESCRIPTION
        data: 键码/宏/描述的原始字节
        """
        payload = bytes([sub_type, mode, key_index]) + data
        self.send_command(DeviceCmd.UPDATE_CUSTOME_KEY, payload)

    # ==============================
    # 图片更新
    # ==============================

    def read_pic_state(self, mode: int) -> dict:
        """读取指定模式的图片状态
        返回: {mode, start_index, pic_length, frame_interval, all_mode_max_pic}
        """
        with self._lock:
            frame = build_device_frame(DeviceCmd.READ_PIC_STATE, bytes([mode]))
            self._resp_event.clear()
            self.tcp.send(PKT_WRITE_CMD, frame)
            payload = self._wait_response(DeviceCmd.READ_PIC_STATE, timeout=5.0)
            # 检查状态码（第一个字节）
            if not payload or payload[0] != 0:
                raise RuntimeError(f"Read pic state failed, status={payload[0] if payload else 'None'}")
            # 跳过状态码，解析实际数据
            return parse_pic_state_response(payload[1:])

    def update_pic(self, mode: int, start: int, count: int, fps: int = 10, time_delay: int = None):
        """更新设备动画参数"""
        if time_delay is None:
            time_delay = int(1000 / fps)
        cmd_data = struct.pack("<BHHH", mode, start, count, time_delay)
        self.send_command(DeviceCmd.UPDATE_PIC, cmd_data)

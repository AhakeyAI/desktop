"""
TCP 客户端 — 与 BLE-to-TCP 桥接器通信
基于 QObject 信号实现线程安全的 UI 集成
"""

import socket
import struct
import threading
from typing import Optional

from PySide6.QtCore import QObject, Signal

from .protocol import build_tcp_packet


class TcpClient(QObject):
    """TCP 客户端，通过信号将接收到的数据传递到主线程"""

    packet_received = Signal(object)  # (pkt_type, data) tuple
    connection_changed = Signal(bool)     # connected

    def __init__(self, parent=None):
        super().__init__(parent)
        self._sock: Optional[socket.socket] = None
        self._connected = False
        self._recv_thread: Optional[threading.Thread] = None
        self._stop = False

    @property
    def connected(self) -> bool:
        return self._connected

    def open(self, host: str, port: int):
        """连接到桥接器"""
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.connect((host, port))
        self._connected = True
        self._stop = False
        self._recv_thread = threading.Thread(target=self._recv_loop, daemon=True)
        self._recv_thread.start()
        self.connection_changed.emit(True)

    def disconnect(self):
        """断开连接"""
        self._stop = True
        self._connected = False
        if self._sock:
            try:
                self._sock.close()
            except Exception:
                pass
            self._sock = None
        self.connection_changed.emit(False)

    def send(self, pkt_type: int, data: bytes = b""):
        """发送 TCP 包"""
        if self._sock and self._connected:
            self._sock.sendall(build_tcp_packet(pkt_type, data))

    def _recv_loop(self):
        """接收线程"""
        try:
            while not self._stop and self._connected:
                header = self._recv_exact(3)
                if not header:
                    break
                pkt_type = header[0]
                length = struct.unpack_from("<H", header, 1)[0]
                data = self._recv_exact(length) if length > 0 else b""
                if data is None and length > 0:
                    break
                # 通过信号发射到主线程（Qt 自动排队）
                self.packet_received.emit((pkt_type, data or b""))
        except (ConnectionResetError, ConnectionAbortedError, OSError):
            pass
        finally:
            self._connected = False
            self.connection_changed.emit(False)

    def _recv_exact(self, count: int) -> Optional[bytes]:
        """精确读取 count 字节"""
        buf = b""
        while len(buf) < count:
            chunk = self._sock.recv(count - len(buf))
            if not chunk:
                return None
            buf += chunk
        return buf

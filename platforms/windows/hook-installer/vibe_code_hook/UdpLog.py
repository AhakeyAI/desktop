import socket
import time


class UdpLog:
    """Simple UDP logger that sends log messages to a remote receiver."""

    LEVEL_DEBUG = "DEBUG"
    LEVEL_INFO = "INFO"
    LEVEL_WARN = "WARN"
    LEVEL_ERROR = "ERROR"

    def __init__(self, host="127.0.0.1", port=9999, tag="APP"):
        self._host = host
        self._port = port
        self._tag = tag
        # self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    def _send(self, level, msg):
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        line = f"[{timestamp}][{self._tag}][{level}] {msg}\n"
        # self._sock.sendto(line.encode("utf-8"), (self._host, self._port))

    def debug(self, msg):
        self._send(self.LEVEL_DEBUG, msg)

    def info(self, msg):
        self._send(self.LEVEL_INFO, msg)

    def warn(self, msg):
        self._send(self.LEVEL_WARN, msg)

    def error(self, msg):
        self._send(self.LEVEL_ERROR, msg)

    def close(self):
        self._sock.close()


import struct
import threading
from enum import IntEnum
import socket
import json
import sys
import os

# ==============================
# TCP Packet Type (桥接层)
# ==============================

PKT_WRITE_DATA      = 0x01  # → BLE 0x7341
PKT_WRITE_CMD       = 0x02  # → BLE 0x7343
PKT_QUERY_STATUS    = 0x03
PKT_QUERY_INFO      = 0x04
PKT_BLE_NOTIFY      = 0x81  # ← BLE 0x7344
PKT_STATUS_RESP     = 0x82
PKT_INFO_RESP       = 0x83


# ==============================
# Device Frame Protocol
# ==============================

FRAME_HEAD = b"\xAA\xBB"
FRAME_TAIL = b"\xCC\xDD"


def build_frame(cmd_type: int, data: bytes = b"") -> bytes:
    return FRAME_HEAD + bytes([cmd_type]) + data + FRAME_TAIL


def parse_frame(raw: bytes):
    if len(raw) < 6:
        return None
    if not (raw.startswith(FRAME_HEAD) and raw.endswith(FRAME_TAIL)):
        return None

    cmd_type = raw[2]
    data = raw[3:-2]
    return cmd_type, data

def parse_status_resp(data: bytes) -> dict:
    """解析 0x82 BLE状态响应"""
    if not data:
        return {}
    offset = 0
    connected = data[offset]; offset += 1
    name_len = data[offset]; offset += 1
    name = data[offset:offset + name_len].decode("utf-8", errors="replace"); offset += name_len
    mac_len = data[offset]; offset += 1
    mac = data[offset:offset + mac_len].decode("utf-8", errors="replace"); offset += mac_len
    is_target = data[offset] if offset < len(data) else 0
    return {
        "connected": bool(connected),
        "name": name,
        "mac": mac,
        "is_target": bool(is_target),
    }


def parse_info_resp(data: bytes) -> dict:
    """解析 0x83 设备信息响应"""
    fields = ["BatteryLevel", "SignalStrength", "FwMain", "FwSub",
              "WorkMode", "LightMode", "SwitchState", "Reserve"]
    result = {}
    for i, name in enumerate(fields):
        result[name] = data[i] if i < len(data) else 0
    return result

def decode_rgb565(
    img,
    x_max=160,
    y_max=126,
    using_head=0,
    is_big_end=False,
    h_align=0,
    v_align=0,
    background_color=0x0
):
    """
    RGB565 编码

    :param img: 输入 BGR 图像 (opencv 格式)
    :param x_max: 目标宽度
    :param y_max: 目标高度
    :param using_head: 是否添加头
    :param is_big_end: 是否大端
    :param h_align: 水平对齐方式
    :param v_align: 垂直对齐方式
    :return: bytes
    """

    h_src, w_src = img.shape[:2]

    # ===== 1. 等比例缩放 =====
    scale = min(x_max / w_src, y_max / h_src)
    new_w = int(w_src * scale)
    new_h = int(h_src * scale)

    resized = cv2.resize(img, (new_w, new_h))

    # ===== 2. 创建背景 =====
    full_img = np.zeros((y_max, x_max, 3), dtype=np.uint8)
    full_img[:,:]=[background_color&0x0FF, background_color&0x0FF00>>8, background_color&0x0FF0000>>16]
    # ===== 3. 计算对齐偏移 =====
    # 水平方向
    if h_align <0:
        x_offset = 0
    elif h_align ==0:
        x_offset = (x_max - new_w) // 2
    elif h_align >0:
        x_offset = x_max - new_w
    else:
        raise ValueError("h_align error")

    # 垂直方向
    if v_align<0:
        y_offset = 0
    elif v_align == 0:
        y_offset = (y_max - new_h) // 2
    elif v_align >0:
        y_offset = y_max - new_h
    else:
        raise ValueError("v_align error")

    # ===== 4. 填充到背景 =====
    full_img[y_offset:y_offset+new_h, x_offset:x_offset+new_w] = resized

    # ===== 5. BGR -> RGB565 (向量化加速) =====
    b = full_img[:, :, 0].astype(np.uint16)
    g = full_img[:, :, 1].astype(np.uint16)
    r = full_img[:, :, 2].astype(np.uint16)

    rgb565 = ((r << 8) & 0xF800) | ((g << 3) & 0x07E0) | (b >> 3)

    # ===== 6. 处理字节序 =====
    if is_big_end:
        high = (rgb565 >> 8).astype(np.uint8)
        low = (rgb565 & 0xFF).astype(np.uint8)
    else:
        high = (rgb565 & 0xFF).astype(np.uint8)
        low = (rgb565 >> 8).astype(np.uint8)

    interleaved = np.stack((high, low), axis=-1).reshape(-1)

    bit = bytearray()

    # ===== 7. 添加头 =====
    if using_head:
        bit.extend([0x55, 0xAA])
        bit.extend([x_max & 0xFF, x_max >> 8])
        bit.extend([y_max & 0xFF, y_max >> 8])

    bit.extend(interleaved.tobytes())

    return bytes(bit)


class TcpClient:
    def __init__(self):
        self.sock: socket.socket | None = None
        self.connected = False
        self._recv_thread: threading.Thread | None = None
        self._stop = False
        self.on_packet = None  # callback(pkt_type, data)
        self.on_disconnect = None

    def _build_packet(self, pkt_type: int, data: bytes = b"") -> bytes:
        length = len(data)
        return struct.pack("<BH", pkt_type, length) + data

    def connect(self, host: str, port: int):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.connect((host, port))
        self.connected = True
        self._stop = False
        self._recv_thread = threading.Thread(target=self._recv_loop, daemon=True)
        self._recv_thread.start()

    def disconnect(self):
        self._stop = True
        self.connected = False
        if self.sock:
            try:
                self.sock.close()
            except Exception:
                pass
        self.sock = None

    def send(self, pkt_type: int, data: bytes = b""):
        if self.sock and self.connected:
            self.sock.sendall(self._build_packet(pkt_type, data))

    def _recv_loop(self):
        try:
            while not self._stop and self.connected:
                header = self._recv_exact(3)
                if not header:
                    break
                pkt_type = header[0]
                length = struct.unpack_from("<H", header, 1)[0]
                data = self._recv_exact(length) if length > 0 else b""
                if data is None and length > 0:
                    break
                if self.on_packet:
                    self.on_packet(pkt_type, data or b"")
        except (ConnectionResetError, ConnectionAbortedError, OSError):
            pass
        finally:
            self.connected = False
            if self.on_disconnect:
                self.on_disconnect()

    def _recv_exact(self, count: int):
        buf = b""
        while len(buf) < count:
            chunk = self.sock.recv(count - len(buf))
            if not chunk:
                return None
            buf += chunk
        return buf

# ==============================
# Device Command Enum
# ==============================

class DeviceCmd(IntEnum):

    SAVE_CONFIG = 0x04  # 保存动图及按键配置信息

    PREPARE_WRITE = 0x80      # 大数据写准备
    WRITE_RESULT  = 0x81      # 数据写结果

    UPDATE_PIC = 0x82      # 图片数据更新
    UPDATE_STATE = 0x90      # 更新 claude code 运行状态



# ==============================
# Device Service (核心业务层)
# ==============================

class DeviceService:

    MAX_CHUNK = 4096

    def __init__(self, tcp_client):
        self.tcp = tcp_client

        self._lock = threading.Lock()
        self._resp_event = threading.Event()
        self._resp_type = None
        self._resp_payload = None
        self._devices_state = None
        self._devices_info = None

        self.tcp.on_packet = self._on_packet

    # ==============================
    # TCP回调
    # ==============================

    def _on_packet(self, pkt_type, data):
        if (pkt_type == PKT_STATUS_RESP):
            self._devices_state = parse_status_resp(data)
            self._resp_event.set()
            return
        if (pkt_type == PKT_INFO_RESP):
            self._devices_info = parse_info_resp(data)
            self._resp_event.set()
            return

        if pkt_type != PKT_BLE_NOTIFY:
            return

        parsed = parse_frame(data)
        if not parsed:
            return

        cmd_type, payload = parsed

        self._resp_type = cmd_type
        self._resp_payload = payload
        self._resp_event.set()

    # ==============================
    # 等待指定Type响应
    # ==============================

    def _wait_response(self, expect_type: int, timeout=5):
        if not self._resp_event.wait(timeout):
            raise TimeoutError(f"Wait response 0x{expect_type:02X} timeout")

        if expect_type>0 and self._resp_type != expect_type:
            raise RuntimeError(
                f"Unexpected response type: 0x{self._resp_type:02X}, "
                f"expect: 0x{expect_type:02X}"
            )

        return self._resp_payload

    # ==============================
    # 普通命令发送
    # ==============================

    def send_command(self, cmd: DeviceCmd, data: bytes = b"", timeout=5, have_ret=True):
        with self._lock:

            frame = build_frame(cmd, data)

            self._resp_event.clear()
            self.tcp.send(PKT_WRITE_CMD, frame)
            if not have_ret:
                return True

            payload = self._wait_response(cmd, timeout)

            if not payload or payload[0] != 0:
                raise RuntimeError(
                    f"Device error, cmd=0x{cmd:02X}, code={payload}"
                )

            return True
    def query_devices_state(self, timeout=5):
        with self._lock:
            self._resp_event.clear()
            self.tcp.send(PKT_QUERY_STATUS)
            payload = self._wait_response(0, timeout)
            return self._devices_state
    def query_devices_info(self, timeout=5):
        with self._lock:
            self._resp_event.clear()
            self.tcp.send(PKT_QUERY_INFO)
            payload = self._wait_response(0, timeout)
            return self._devices_info

    # ==============================
    # 大批量数据写入
    # ==============================

    def write_large_data(self, address: int, data: bytes, timeout=5):

        if address % 4096 != 0:
            raise ValueError("Address must be 4K aligned")

        total_len = len(data)
        offset = 0

        with self._lock:

            while offset < total_len:

                chunk = data[offset:offset + self.MAX_CHUNK]
                chunk_len = len(chunk)
                current_addr = address + offset

                # --------------------------
                # 1. 发送 PREPARE_WRITE
                # --------------------------
                cmd_data = struct.pack("<BHI", 0, chunk_len, current_addr)

                self._resp_event.clear()
                self.tcp.send(
                    PKT_WRITE_CMD,
                    build_frame(DeviceCmd.PREPARE_WRITE, cmd_data)
                )

                payload = self._wait_response(DeviceCmd.PREPARE_WRITE, timeout)

                if not payload or payload[0] != 0:
                    raise RuntimeError(
                        f"Prepare write failed at offset {offset}"
                    )

                # --------------------------
                # 2. 发送数据块
                # --------------------------
                self._resp_event.clear()
                self.tcp.send(PKT_WRITE_DATA, chunk)

                payload = self._wait_response(DeviceCmd.WRITE_RESULT, timeout)

                if not payload or payload[0] != 0:
                    raise RuntimeError(
                        f"Write chunk failed at offset {offset}"
                    )

                offset += chunk_len

                print(f"Written {offset}/{total_len}")

        return True
    
    def update_pic(self, mode, start, len, fps=10,time_delay=None):
        if time_delay is None:
            time_delay = int(1000/fps)
        cmd_data = struct.pack("<BHHH", mode, start, len, time_delay)
        self.send_command(DeviceCmd.UPDATE_PIC,cmd_data)
    

class ClaudeState(IntEnum):
    CL_Notification =0
    CL_PermissionRequest=1
    CL_PostToolUse=2
    CL_PreToolUse=3
    CL_SessionStart=4
    CL_Stop=5
    CL_TaskCompleted=6
    CL_UserPromptSubmit=7
    CL_SessionEnd=8


def is_port_open(host, port, timeout=0.3):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(timeout)
        result = s.connect_ex((host, port))
        return result == 0

# print(is_port_open("127.0.0.1", 9000))

DEFAULT_CONFIG = {
    "server_ip": "127.0.0.1",
    "server_port": 9000
}
from UdpLog import UdpLog

def is_frozen():
    """判断当前是否为 PyInstaller 打包的可执行程序。"""
    return getattr(sys, 'frozen', False)


def get_self_path() -> str:
    """获取当前程序自身的路径（exe 或 py 脚本）。"""
    if is_frozen():
        return sys.executable
    else:
        return os.path.abspath(__file__)


def load_config():
    log = UdpLog(tag="dist")
    # 获取当前脚本所在目录
    base_dir = os.path.dirname(get_self_path())
    config_path = os.path.join(base_dir, "config_client.json")
    log.info(config_path)

    # 如果文件不存在，创建默认配置
    if not os.path.exists(config_path):
        with open(config_path, "w", encoding="utf-8") as f:
            json.dump(DEFAULT_CONFIG, f, indent=4)
        # print("未找到 config.json，已创建默认配置")
        return DEFAULT_CONFIG["server_ip"], DEFAULT_CONFIG["server_port"]

    # 文件存在，尝试读取
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            config = json.load(f)

        # 补全缺失字段
        updated = False
        for key in DEFAULT_CONFIG:
            if key not in config:
                config[key] = DEFAULT_CONFIG[key]
                updated = True

        # 如果有字段缺失则写回
        if updated:
            with open(config_path, "w", encoding="utf-8") as f:
                json.dump(config, f, indent=4)

        return config["server_ip"], config["server_port"]

    except (json.JSONDecodeError, OSError):
        # 文件损坏，重建
        # print("config.json 格式错误，已重建默认配置")
        with open(config_path, "w", encoding="utf-8") as f:
            json.dump(DEFAULT_CONFIG, f, indent=4)

        return DEFAULT_CONFIG["server_ip"], DEFAULT_CONFIG["server_port"]


def send_new_state(state):
    ip, port = load_config()
    if is_port_open(ip, port):
        bridge = TcpClient() 
        bridge.connect(ip, port)
        device = DeviceService(bridge)
        cmd_data = struct.pack("<B", state)
        device.send_command(DeviceCmd.UPDATE_STATE, cmd_data, have_ret=False)
        ret = device.query_devices_state()
        if ret["is_target"]:
            # print("yes")
            return device.query_devices_info()
        else:
            return None
    return None

    # b = decode_rgb565(img)
    # device.write_large_data(0, data)
# send_new_state(ClaudeState.CL_Notification)
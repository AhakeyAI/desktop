"""
简易 TCP 桥接器模拟器

用途:
- 在没有真实 BLE 桥接/键盘的情况下，模拟桥接设备的最小行为
- 让本项目中的 hooks (ble_command_send.send_new_state) 能够连上服务器并获得
  合法的状态/设备信息回复, 从而完整跑通 Cursor ↔ 上位机 ↔ (假)设备 这条链路

协议依据:
- 与 hook/ble_command_send.py 中的协议保持一致:
  - TCP 包: [Type:1][Length:2 LE][Data:N]
  - 设备帧: [0xAA,0xBB][Cmd:1][Data:N][0xCC,0xDD]
  - PKT_QUERY_STATUS(0x03) → PKT_STATUS_RESP(0x82)
  - PKT_QUERY_INFO(0x04)   → PKT_INFO_RESP(0x83)

运行方法:
1. 在虚拟环境或系统 Python 中运行本脚本:
   python hook/fake_bridge.py

2. 确认 hook/config_client.json 中的 server_ip / server_port 与本脚本一致
   (默认监听 127.0.0.1:9000, 和 ble_command_send.DEFAULT_CONFIG 保持一致)

3. 触发任意 hook (例如在 Cursor 中新建会话触发 SessionStart),
   观察本脚本的终端输出, 确认收发的包符合预期。
"""

import socket
import struct
from typing import Tuple


# 与 ble_command_send.py 保持一致的常量
PKT_WRITE_DATA = 0x01
PKT_WRITE_CMD = 0x02
PKT_QUERY_STATUS = 0x03
PKT_QUERY_INFO = 0x04
PKT_BLE_NOTIFY = 0x81
PKT_STATUS_RESP = 0x82
PKT_INFO_RESP = 0x83

FRAME_HEAD = b"\xAA\xBB"
FRAME_TAIL = b"\xCC\xDD"


def build_tcp_packet(pkt_type: int, payload: bytes = b"") -> bytes:
    """构建 TCP 包: [Type:1][Length:2 LE][Data:N]"""
    return struct.pack("<BH", pkt_type, len(payload)) + payload


def parse_device_frame(data: bytes) -> Tuple[int, bytes] | None:
    """解析设备帧, 返回 (cmd_type, payload)"""
    if len(data) < 6:
        return None
    if not (data.startswith(FRAME_HEAD) and data.endswith(FRAME_TAIL)):
        return None
    cmd = data[2]
    payload = data[3:-2]
    return cmd, payload


def handle_client(conn: socket.socket, addr):
    print(f"[bridge] client connected from {addr}")
    try:
        while True:
            try:
                header = conn.recv(3)
                if not header:
                    print("[bridge] client disconnected")
                    break
                pkt_type = header[0]
                length = struct.unpack_from("<H", header, 1)[0]
                payload = conn.recv(length) if length > 0 else b""

                print(f"[bridge] recv pkt_type=0x{pkt_type:02X}, len={length}")

                if pkt_type == PKT_WRITE_CMD:
                    parsed = parse_device_frame(payload)
                    if not parsed:
                        print("[bridge] invalid device frame")
                        continue
                    cmd, cmd_payload = parsed
                    print(f"[bridge] WRITE_CMD, cmd=0x{cmd:02X}, payload_len={len(cmd_payload)}")
                    # 对于测试, UPDATE_STATE 等命令直接忽略即可, 不需要回包

                elif pkt_type == PKT_QUERY_STATUS:
                    # 返回一个简单的“已连接 + 是目标设备”状态
                    name = "FakeVibeKeyboard".encode("utf-8")
                    mac = "11:22:33:44:55:66".encode("utf-8")
                    resp = bytearray()
                    resp.append(1)  # connected = True
                    resp.append(len(name))
                    resp.extend(name)
                    resp.append(len(mac))
                    resp.extend(mac)
                    resp.append(1)  # is_target = True

                    conn.sendall(build_tcp_packet(PKT_STATUS_RESP, bytes(resp)))
                    print("[bridge] sent STATUS_RESP")

                elif pkt_type == PKT_QUERY_INFO:
                    # 返回 8 个字节的设备信息:
                    # [BatteryLevel, SignalStrength, FwMain, FwSub,
                    #  WorkMode, LightMode, SwitchState, Reserve]
                    # 这里模拟 SwitchState=0 (auto 模式)
                    battery = 100
                    signal = 80
                    fw_main = 1
                    fw_sub = 0
                    work_mode = 0
                    light_mode = 0
                    switch_state = 0  # 0=auto, 1=manual
                    reserve = 0
                    resp = bytes(
                        [
                            battery,
                            signal,
                            fw_main,
                            fw_sub,
                            work_mode,
                            light_mode,
                            switch_state,
                            reserve,
                        ]
                    )
                    conn.sendall(build_tcp_packet(PKT_INFO_RESP, resp))
                    print("[bridge] sent INFO_RESP (SwitchState=0)")

                else:
                    print(f"[bridge] unhandled pkt_type=0x{pkt_type:02X}")
            except ConnectionResetError:
                print("[bridge] client reset connection")
                break
    finally:
        conn.close()
        print("[bridge] connection closed")


def main():
    host = "127.0.0.1"
    port = 9000
    print(f"[bridge] listening on {host}:{port} ...")

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((host, port))
        s.listen(1)
        while True:
            conn, addr = s.accept()
            handle_client(conn, addr)


if __name__ == "__main__":
    main()


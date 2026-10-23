import asyncio
import struct
import sys
from bleak import BleakScanner, BleakClient, BleakError

# GATT 特征 UUID (与 C# 版保持一致)
UART_SERVICE_UUID = "0000fee9-0000-1000-8000-00805f9b34fb"
CHAR_DATA_WRITE = "00007341-0000-1000-8000-00805f9b34fb"
CHAR_CMD_WRITE = "00007343-0000-1000-8000-00805f9b34fb"
CHAR_NOTIFY = "00007344-0000-1000-8000-00805f9b34fb"

# TCP 帧协议 (与 BleTcpPacket.java 一致)
# [Type:1][Length:2 LE][Data:N]
TYPE_WRITE_DATA = 0x01
TYPE_WRITE_CMD = 0x02
TYPE_QUERY_STATUS = 0x03
TYPE_QUERY_DEVICE_INFO = 0x04
TYPE_BLE_NOTIFY = 0x81
TYPE_STATUS_RESP = 0x82
TYPE_DEVICE_INFO_RESP = 0x83

client = None
notify_char = None
device_status = bytes(8)
target_name = ""
target_mac = ""


def parse_frame(data):
    if len(data) < 3:
        return
    ptype = data[0]
    plen = struct.unpack_from("<H", data, 1)[0]
    payload = data[3:3 + plen]
    return ptype, payload


def build_frame(ptype, payload=b""):
    return struct.pack("<BH", ptype, len(payload)) + payload


async def handle_client(reader, writer):
    global client, notify_char, device_status
    addr = writer.get_extra_info("peername")
    print(f"[TCP] 客户端连接: {addr}")

    while True:
        try:
            header = await reader.readexactly(3)
        except (asyncio.IncompleteReadError, ConnectionError):
            break

        ptype = header[0]
        plen = struct.unpack_from("<H", header, 1)[0]
        payload = b""
        if plen > 0:
            try:
                payload = await reader.readexactly(plen)
            except (asyncio.IncompleteReadError, ConnectionError):
                break

        if ptype == TYPE_WRITE_DATA:
            if client and client.is_connected:
                for i in range(0, len(payload), 200):
                    chunk = payload[i:i + 200]
                    await client.write_gatt_char(CHAR_DATA_WRITE, chunk, response=True)
                print(f"[BLE] 数据写入 {len(payload)} 字节")

        elif ptype == TYPE_WRITE_CMD:
            if client and client.is_connected:
                for i in range(0, len(payload), 20):
                    chunk = payload[i:i + 20]
                    await client.write_gatt_char(CHAR_CMD_WRITE, chunk, response=True)
                print(f"[BLE] 命令写入 {len(payload)} 字节")

        elif ptype == TYPE_QUERY_STATUS:
            connected = client is not None and client.is_connected
            name_bytes = target_name.encode("utf-8")
            mac_bytes = target_mac.encode("utf-8")
            data = struct.pack("B", 1 if connected else 0)
            data += struct.pack("B", len(name_bytes)) + name_bytes
            data += struct.pack("B", len(mac_bytes)) + mac_bytes
            data += struct.pack("B", 1 if connected else 0)
            writer.write(build_frame(TYPE_STATUS_RESP, data))
            await writer.drain()

        elif ptype == TYPE_QUERY_DEVICE_INFO:
            writer.write(build_frame(TYPE_DEVICE_INFO_RESP, device_status))
            await writer.drain()

    print(f"[TCP] 客户端断开: {addr}")
    writer.close()


def notify_handler(sender, data):
    global device_status
    # 解析设备状态通知: AA BB 00 [8字节状态] CC DD
    if len(data) == 13 and data[:3] == b"\xaa\xbb\x00" and data[-2:] == b"\xcc\xdd":
        device_status = data[3:11]
        print(f"[BLE] 设备状态更新: {data[3:11].hex()}")


async def auto_connect():
    global client, notify_char, target_name, target_mac

    while True:
        try:
            print("[BLE] 正在扫描设备...")
            devices = await BleakScanner.discover(timeout=5)

            target = None
            for d in devices:
                if d.name and "AhaKey" in d.name:
                    target = d
                    break

            if target is None:
                print("[BLE] 未找到目标设备，5秒后重试...")
                await asyncio.sleep(5)
                continue

            target_name = target.name or ""
            target_mac = target.address or ""
            print(f"[BLE] 发现目标: {target_name} [{target_mac}]")

            client = BleakClient(target)
            await client.connect()
            print(f"[BLE] 已连接: {target_name}")

            # 发现服务和特征
            for service in client.services:
                for char in service.characteristics:
                    if char.uuid == CHAR_NOTIFY:
                        notify_char = char
                        await client.start_notify(CHAR_NOTIFY, notify_handler)
                        print("[BLE] 通知已启用")
                    if char.uuid == CHAR_CMD_WRITE:
                        # 发送状态查询
                        query = bytes([0xAA, 0xBB, 0x00, 0xCC, 0xDD])
                        await client.write_gatt_char(CHAR_CMD_WRITE, query, response=True)
                        print("[BLE] 已发送状态查询")

            # 等待断开
            await client.wait_for_disconnect()
            print("[BLE] 设备已断开，5秒后重新连接...")

        except Exception as e:
            print(f"[BLE] 错误: {e}")

        client = None
        notify_char = None
        await asyncio.sleep(5)


async def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9000

    # 启动 BLE 自动连接
    asyncio.create_task(auto_connect())

    # 启动 TCP 服务器
    server = await asyncio.start_server(handle_client, "0.0.0.0", port)
    print(f"[TCP] 服务器启动: 0.0.0.0:{port}")

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())

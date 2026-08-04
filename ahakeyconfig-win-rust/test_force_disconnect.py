#!/usr/bin/env python3
"""
测试 force_disconnect 的可行性:
1. 拿到 AhaKey BLE device handle
2. Close() 触发断开
3. AhaKey 应该开始广播
"""
import asyncio
from winrt.windows.devices.bluetooth import BluetoothLEDevice


async def main():
    mac_str = "DC:04:5A:93:DF:2C"
    parts = mac_str.split(":")
    b = bytes(int(p, 16) for p in parts)
    mac = int.from_bytes(b, "little")
    print(f"[test] MAC {mac_str} → {mac:#x}")

    # 这个可能会失败,因为 AhaKey 不是当前配对设备
    print("[test] trying FromBluetoothAddressAsync...")
    device = await BluetoothLEDevice.from_bluetooth_address_async(mac)
    if device is None:
        print("[test] ✗ device is None (AhaKey not in BLE pairing list)")
        print("[test] 这种情况下,FromBluetoothAddressAsync 返回 None,")
        print("[test] 不能调用 Close() 强制断开。")
        print("[test] → 只能让用户手动在 Windows 蓝牙设置里'断开'AhaKey")
        return

    name = device.name or ""
    print(f"[test] ✓ device name='{name}' status={device.connection_status}")

    # 触发 Close
    print("[test] calling device.Close()...")
    try:
        device.close()
        print("[test] ✓ Close() succeeded")
        print("[test] AhaKey should now be in GAPROLE_WAITING + broadcasting")
    except Exception as e:
        print(f"[test] ✗ Close() failed: {e}")


if __name__ == "__main__":
    asyncio.run(main())
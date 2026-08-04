#!/usr/bin/env python3
"""
AhaKey 5A93 BLE 连接诊断脚本
- 测试 WinRT FromBluetoothAddressAsync 能否拿到已配对设备的句柄
- 测试 GetGattServicesAsync 能否触发 GATT 连接
"""
import asyncio
import sys
from winrt.windows.devices.bluetooth import BluetoothLEDevice
from winrt.windows.devices.bluetooth.genericattributeprofile import GattCharacteristic


async def probe(mac: int):
    print(f"[probe] testing FromBluetoothAddressAsync({mac:#x})...")
    device = await BluetoothLEDevice.from_bluetooth_address_async(mac)
    if device is None:
        print(f"[probe] ✗ device is None — AhaKey {mac:#x} NOT paired with this PC")
        return False

    name = device.name or ""
    addr = device.bluetooth_address
    status = device.connection_status
    print(f"[probe] ✓ got device: name='{name}' addr={addr:#x} status={status}")

    if status.name == "Connected":
        print(f"[probe] ✓ already connected! Will try GATT services...")
    else:
        print(f"[probe] ! device not yet connected, requesting GATT services...")

    # 触发 GATT 连接协商
    print(f"[probe] calling GetGattServicesAsync()...")
    try:
        result = await device.get_gatt_services_async()
        status_code = result.status
        services = result.services
        print(f"[probe] ✓ GetGattServicesAsync done: status={status_code} count={services.size if services else 0}")

        if services:
            for i in range(services.size):
                svc = services[i]
                print(f"[probe]   service {i}: uuid={svc.uuid}")
                chars_result = await svc.get_characteristics_async()
                for j in range(chars_result.characteristics.size if chars_result.characteristics else 0):
                    c = chars_result.characteristics[j]
                    print(f"[probe]     char {j}: uuid={c.uuid} props={c.characteristic_properties}")

        # 现在再检查连接状态
        new_status = device.connection_status
        print(f"[probe] after GATT: status={new_status}")
        return True
    except Exception as e:
        print(f"[probe] ✗ GetGattServicesAsync failed: {e}")
        return False


async def main():
    # DC:04:5A:93:DF:2C -> little-endian bytes -> integer
    mac_str = "DC:04:5A:93:DF:2C"
    parts = mac_str.split(":")
    b = bytes(int(p, 16) for p in parts)
    mac = int.from_bytes(b, "little")
    print(f"[main] MAC {mac_str} → integer {mac:#x}")

    ok = await probe(mac)
    print(f"\n[main] {'AhaKey is reachable via WinRT' if ok else 'AhaKey is NOT reachable'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
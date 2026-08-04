#!/usr/bin/env python3
"""
关键验证: AhaKey 5A93 通过 WinRT FromBluetoothAddressAsync + GetGattServicesAsync
能否拿到 GATT 服务列表(包含 0x7341/7343/7344)
"""
import asyncio
from winrt.windows.devices.bluetooth import BluetoothLEDevice
from winrt.windows.devices.bluetooth.genericattributeprofile import (
    GattCharacteristicProperties,
)


async def main():
    mac_str = "DC:04:5A:93:DF:2C"
    parts = mac_str.split(":")
    b = bytes(int(p, 16) for p in parts)
    mac = int.from_bytes(b, "little")
    print(f"[test] MAC {mac_str} → {mac:#x}")

    device = await BluetoothLEDevice.from_bluetooth_address_async(mac)
    if device is None:
        print("[test] ✗ device is None")
        return

    name = device.name or ""
    print(f"[test] ✓ device name='{name}' connection_status={device.connection_status}")

    # 触发 GATT 服务发现
    print("[test] calling GetGattServicesAsync()...")
    services_result = await device.get_gatt_services_async()
    print(f"[test] status={services_result.status} count={services_result.services.size if services_result.services else 0}")

    if services_result.services:
        for i in range(services_result.services.size):
            svc = services_result.services[i]
            print(f"[test]   service {i}: uuid={svc.uuid}")

            chars_result = await svc.get_characteristics_async()
            if chars_result.characteristics:
                for j in range(chars_result.characteristics.size):
                    ch = chars_result.characteristics[j]
                    print(f"[test]     char {j}: uuid={ch.uuid} props={ch.characteristic_properties}")

    # 重点关注: 0x7341, 0x7343, 0x7344 特征是否存在
    print("\n[test] looking for AhaKey service 0x7340...")
    target_uuid = "00007340-0000-1000-8000-00805f9b34fb"
    target_svc = None
    if services_result.services:
        for i in range(services_result.services.size):
            svc = services_result.services[i]
            if str(svc.uuid).lower() == target_uuid:
                target_svc = svc
                break

    if target_svc:
        print("[test] ✓ found AhaKey service 0x7340!")
        chars = await target_svc.get_characteristics_async()
        if chars.characteristics:
            for j in range(chars.characteristics.size):
                ch = chars.characteristics[j]
                print(f"[test]   char uuid={ch.uuid}")
    else:
        print("[test] ✗ AhaKey service 0x7340 NOT found")
        print("[test]   this means AhaKey doesn't expose its custom BLE config service")


if __name__ == "__main__":
    asyncio.run(main())
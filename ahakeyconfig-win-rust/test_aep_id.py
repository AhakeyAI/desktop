#!/usr/bin/env python3
"""
关键测试: 用 AEP id 能否绕过已连接状态,拿到 AhaKey BLE device
"""
import asyncio
from winrt.windows.devices.bluetooth import BluetoothLEDevice


async def main():
    # 你的电脑蓝牙 MAC: b0:3c:dc:ad:75:fe (从之前的扫描结果)
    pc_mac = "b0:3c:dc:ad:75:fe"
    dev_mac = "dc:04:5a:93:df:2c"

    aep_id = f"BluetoothLE#BluetoothLE{pc_mac}-{dev_mac}"
    print(f"[test] AEP id: {aep_id}")
    print(f"[test] calling FromIdAsync...")

    try:
        device = await BluetoothLEDevice.from_id_async(aep_id)
        if device is None:
            print("[test] ✗ device is None")
            return

        name = device.name or ""
        print(f"[test] ✓ Got device! name='{name}' status={device.connection_status}")

        # 拿 GATT services
        print("[test] calling GetGattServicesAsync...")
        result = await device.get_gatt_services_async()
        print(f"[test] status={result.status} count={result.services.size if result.services else 0}")

        if result.services:
            for i in range(result.services.size):
                svc = result.services[i]
                uuid_str = str(svc.uuid)
                print(f"[test]   service {i}: uuid={uuid_str}")

                chars = await svc.get_characteristics_async()
                if chars.characteristics:
                    for j in range(chars.characteristics.size):
                        ch = chars.characteristics[j]
                        print(f"[test]     char {j}: uuid={ch.uuid}")
    except Exception as e:
        print(f"[test] ✗ exception: {e}")


if __name__ == "__main__":
    asyncio.run(main())
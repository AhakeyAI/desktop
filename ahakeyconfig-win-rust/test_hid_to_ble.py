#!/usr/bin/env python3
"""
通过 HID device ID 打开 BLE 设备
"""
import asyncio
from winrt.windows.devices.bluetooth import BluetoothLEDevice


async def main():
    # 这是从 HID 路径里提取的 AhaKey device id
    device_id = r"\\?\HID#{00001812-0000-1000-8000-00805f9b34fb}_Dev_VID&0107d7_PID&0000_REV&0110_dc045a93df2c#9&33faea76&0&0000#{4d1e55b2-f16f-11cf-88cb-001111000030}\KBD"

    print(f"[test] BluetoothLEDevice::FromIdAsync({device_id[:80]}...)")
    try:
        op = BluetoothLEDevice.from_id_async(device_id)
        device = op.get_results()
        if not device:
            print("[test] ✗ device is None")
            return
        print(f"[test] ✓ Got BLE device!")
        print(f"[test]   name='{device.name}'")
        print(f"[test]   bluetooth_address={device.bluetooth_address:#x}")
        print(f"[test]   connection_status={device.connection_status}")

        # 拿 GATT services
        print("[test] calling GetGattServicesAsync...")
        services_result = await device.get_gatt_services_async()
        print(f"[test]   status={services_result.status} count={services_result.services.size if services_result.services else 0}")

        if services_result.services:
            for i in range(services_result.services.size):
                svc = services_result.services[i]
                print(f"[test]     svc {i}: uuid={svc.uuid}")
                chars = await svc.get_characteristics_async()
                if chars.characteristics:
                    for j in range(chars.characteristics.size):
                        ch = chars.characteristics[j]
                        print(f"[test]       char {j}: uuid={ch.uuid}")

    except Exception as e:
        print(f"[test] ✗ EXCEPTION: {e}")


if __name__ == "__main__":
    asyncio.run(main())
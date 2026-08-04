#!/usr/bin/env python3
"""
完整测试: 用 AEP id 连接 AhaKey,订阅 0x7344 notify,发一个状态查询命令
"""
import asyncio
import os
from winrt.windows.devices.bluetooth import BluetoothLEDevice
from winrt.windows.devices.bluetooth.genericattributeprofile import (
    GattClientCharacteristicConfigurationDescriptorValue,
)
from winrt.windows.storage.streams import DataWriter


async def main():
    pc_mac = "b0:3c:dc:ad:75:fe"
    dev_mac = "dc:04:5a:93:df:2c"
    aep_id = f"BluetoothLE#BluetoothLE{pc_mac}-{dev_mac}"

    print(f"[test] FromIdAsync({aep_id})...")
    device = await BluetoothLEDevice.from_id_async(aep_id)
    if device is None:
        print("[test] ✗ device is None")
        return
    print(f"[test] ✓ device name='{device.name}' status={device.connection_status}")

    # 拿 SimpleProfile 0x7340
    print("[test] GetGattServicesAsync...")
    services_result = await device.get_gatt_services_async()
    if not services_result.services:
        print("[test] ✗ no services")
        return

    target_svc = None
    for i in range(services_result.services.size):
        svc = services_result.services[i]
        uuid_str = str(svc.uuid).lower()
        if "7340" in uuid_str:
            target_svc = svc
            print(f"[test] ✓ found SimpleProfile: {uuid_str}")
            break

    if target_svc is None:
        print("[test] ✗ SimpleProfile 0x7340 not found")
        return

    # 拿 characteristics
    print("[test] GetCharacteristicsAsync...")
    chars = await target_svc.get_characteristics_async()
    if not chars.characteristics:
        print("[test] ✗ no characteristics")
        return

    notify_char = None
    write_char = None
    for j in range(chars.characteristics.size):
        ch = chars.characteristics[j]
        uuid_str = str(ch.uuid).lower()
        props = ch.characteristic_properties
        print(f"[test]   char {j}: uuid={uuid_str} props={props}")
        if "7344" in uuid_str:
            notify_char = ch
        if "7343" in uuid_str:
            write_char = ch

    if not notify_char:
        print("[test] ✗ notify char 0x7344 not found")
        return
    if not write_char:
        print("[test] ✗ write char 0x7343 not found")
        return

    # 订阅 notify
    print("[test] subscribing to 0x7344 notify...")
    status = await notify_char.write_client_characteristic_configuration_descriptor_async(
        GattClientCharacteristicConfigurationDescriptorValue.NOTIFY
    )
    print(f"[test] subscribe status={status}")

    if status != 0:  # Success
        print("[test] ✗ subscribe failed")
        return

    # 等待订阅生效
    await asyncio.sleep(0.5)

    # 发状态查询命令 0xAA 0xBB 0x00 0xCC 0xDD
    print("[test] sending status query: AA BB 00 CC DD")
    cmd = bytes([0xAA, 0xBB, 0x00, 0xCC, 0xDD])
    writer = DataWriter()
    writer.write_bytes(cmd)
    buf = writer.detach_buffer()
    write_status = await write_char.write_value_with_result_async(buf)
    print(f"[test] write status={write_status}")

    # 等 3 秒看 notify
    print("[test] waiting 3s for notify...")
    notify_data = []
    def on_notify(sender, args):
        print(f"[test] NOTIFY received! len={args.characteristic_value.length}")
        data = bytes(args.characteristic_value)
        print(f"[test] data: {data.hex()}")
        notify_data.append(data)

    notify_char.add_value_changed(lambda s, a: on_notify(s, a))
    await asyncio.sleep(3)

    if not notify_data:
        print("[test] ✗ no notify received in 3s")
        print("[test] AhaKey 没响应 → 它的 BLE 通道没在运行 GATT server")
    else:
        print(f"[test] ✓ received {len(notify_data)} notify packets!")


if __name__ == "__main__":
    asyncio.run(main())
#!/usr/bin/env python3
"""
AhaKey 5A93 深度诊断:验证隐私地址假设
- 即使设备已连接,WinRT DeviceWatcher 也会看到它的广播包
- 但广播包里的 MAC 是随机私有地址,不是 DC:04:5A:93:DF:2C
- 我们要找的是哪个 MAC?
"""
import asyncio
from winrt.windows.devices.enumeration import (
    DeviceInformation,
    DeviceInformationKind,
)


async def deep_scan():
    print("[deep] DeviceWatcher for ALL BLE devices, scan for 30s...")
    watcher = DeviceInformation.create_watcher_with_kind_aqs_filter_and_additional_properties(
        '(System.Devices.Aep.ProtocolId:="{bb7bb05e-5972-42b5-94fc-76eaa7084d49}")',
        [
            "System.Devices.Aep.DeviceAddress",
            "System.Devices.Aep.Bluetooth.Le.IsConnectable",
        ],
        DeviceInformationKind.ASSOCIATION_ENDPOINT,
    )

    all_devices = {}  # id → (name, addr)
    loop = asyncio.get_event_loop()

    def on_added(sender, info):
        addr_obj = info.properties.get("System.Devices.Aep.DeviceAddress")
        # BluetoothAddress 是 IReference<UInt64> 类型,要从 IPropertyValue 提取
        addr = ""
        if addr_obj:
            try:
                # 用 cast 转到 IPropertyValue
                from winrt.windows.foundation import IPropertyValue
                pv = addr_obj.cast(IPropertyValue)
                if pv:
                    addr_uint64 = pv.get_uint64()
                    addr = f"{addr_uint64:#x}"
            except Exception:
                addr = str(addr_obj)

        name = info.name or ""
        all_devices[info.id] = (name, addr, info)
        print(f"[deep] + name='{name}' addr={addr} id='{info.id}'")

    def on_updated(sender, update):
        # 更新事件 — name 可能从空变成 'AhaKey 5A93'
        try:
            new_info = None
            for did, (n, a, inf) in list(all_devices.items()):
                if did == str(update.id):
                    # 重新查 properties
                    pass
        except Exception:
            pass

    token_added = watcher.add_added(on_added)
    watcher.start()

    await asyncio.sleep(30)
    watcher.stop()
    watcher.remove_added(token_added)

    print(f"\n[deep] total devices collected: {len(all_devices)}")
    print("[deep] Looking for AhaKey-like devices (case-insensitive 'ahakey' in name)...")
    candidates = []
    for did, (name, addr, info) in all_devices.items():
        if name and "ahakey" in name.lower():
            candidates.append((did, name, addr, info))
            print(f"[deep]   ✓ AHAKEY CANDIDATE: id='{did}' name='{name}' addr='{addr}'")

    if not candidates:
        print("[deep] ✗ NO AhaKey device found in 30s scan")
        print("[deep] Hypothesis: AhaKey 5A93 is NOT advertising — verify physically")

    return candidates


async def main():
    await deep_scan()


if __name__ == "__main__":
    asyncio.run(main())
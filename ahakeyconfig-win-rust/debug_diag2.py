#!/usr/bin/env python3
"""
测试所有可能的 FromXxxAsync API
"""
import asyncio
from winrt.windows.devices.enumeration import (
    DeviceInformation,
    DeviceInformationKind,
)


async def probe_find_all():
    """用 DeviceWatcher 拿所有 BLE 设备"""
    print("[probe_find_all] creating DeviceWatcher for all BLE...")
    watcher = DeviceInformation.create_watcher_with_kind_aqs_filter_and_additional_properties(
        '(System.Devices.Aep.ProtocolId:="{bb7bb05e-5972-42b5-94fc-76eaa7084d49}")',
        ["System.Devices.Aep.DeviceAddress"],
        DeviceInformationKind.ASSOCIATION_ENDPOINT,
    )

    found = []
    done = asyncio.Event()
    loop = asyncio.get_event_loop()

    def on_added(sender, info):
        addr = info.properties.get("System.Devices.Aep.DeviceAddress") or ""
        name = info.name or ""
        print(f"[probe_find_all]   + name='{name}' addr='{addr}' id='{info.id}'")
        found.append((name, addr, info.id))
        loop.call_soon_threadsafe(done.set)

    def on_updated(sender, update):
        pass

    token_added = watcher.add_added(on_added)
    token_updated = watcher.add_updated(on_updated)
    watcher.start()
    print("[probe_find_all] watcher started, waiting 15s for first device...")

    try:
        await asyncio.wait_for(done.wait(), timeout=15)
    except asyncio.TimeoutError:
        print("[probe_find_all] timeout")
    finally:
        watcher.stop()
        watcher.remove_added(token_added)
        watcher.remove_updated(token_updated)

    print(f"[probe_find_all] found {len(found)} devices")
    return found


async def probe_find_by_name():
    """找名称含 'AhaKey' 的设备"""
    print("\n[probe_find_by_name] searching for 'AhaKey'...")
    aqs_filter = (
        '(System.Devices.Aep.ProtocolId:="{bb7bb05e-5972-42b5-94fc-76eaa7084d49}")'
        ' AND (System.ItemNameDisplay:LIKE="*AhaKey*" OR System.Devices.Aep.DeviceAddress:="*DC045A93DF2C*")'
    )
    try:
        collection = await DeviceInformation.find_all_async_aqs_filter(aqs_filter)
        print(f"[probe_find_by_name] found {collection.size} devices with name filter")
        for i in range(collection.size):
            info = collection[i]
            addr = info.properties.get("System.Devices.Aep.DeviceAddress") or ""
            print(f"[probe_find_by_name]   - name='{info.name}' addr='{addr}' id='{info.id}'")
            if "AhaKey" in (info.name or "") or "DC045A93DF2C" in (info.id or ""):
                print(f"[probe_find_by_name]     ^^^ MATCH - trying FromIdAsync...")
                from winrt.windows.devices.bluetooth import BluetoothLEDevice
                device = await BluetoothLEDevice.from_id_async(info.id)
                if device:
                    print(f"[probe_find_by_name]     ✓ BluetoothLEDevice name='{device.name}' status={device.connection_status}")
                else:
                    print(f"[probe_find_by_name]     ✗ BluetoothLEDevice is None")
    except Exception as e:
        print(f"[probe_find_by_name] failed: {e}")


async def main():
    await probe_find_all()
    await probe_find_by_name()


if __name__ == "__main__":
    asyncio.run(main())
#!/usr/bin/env python3
"""
用 python winrt 测试不同的 AQS 过滤器,找到能匹配 VID 1EA7 PID 0064 的那一个
"""
import asyncio
from winrt.windows.devices.enumeration import DeviceInformation


async def test_aqs(name, aqs):
    print(f"\n[test] === {name} ===")
    print(f"[test] AQS: {aqs}")
    try:
        col = await DeviceInformation.find_all_async_aqs_filter(aqs)
        print(f"[test] → found {col.size} devices")
        for i in range(col.size):
            info = col[i]
            print(f"[test]   - name='{info.name}' id='{info.id}'")
            props = info.properties
            for key in props:
                print(f"[test]      {key} = {props[key]}")
    except Exception as e:
        print(f"[test] ✗ failed: {e}")


async def main():
    # 测试 1: 不带过滤,看 HIDClass 能不能用
    await test_aqs(
        "HIDClass basic",
        'System.Devices.InterfaceClassGuid:="{4D1E55B2-F16F-11CF-88CB-001111000030}"',
    )

    # 测试 2: 加 VID/PID
    await test_aqs(
        "HIDClass + VID/PID",
        'System.Devices.InterfaceClassGuid:="{4D1E55B2-F16F-11CF-88CB-001111000030}" '
        'AND System.DeviceInterface.Hid.VendorId:=0x1EA7 '
        'AND System.DeviceInterface.Hid.ProductId:=0x64',
    )

    # 测试 3: 不带 InterfaceClassGuid,只用 VID/PID
    await test_aqs(
        "VID/PID only",
        'System.DeviceInterface.Hid.VendorId:=0x1EA7 '
        'AND System.DeviceInterface.Hid.ProductId:=0x64',
    )

    # 测试 4: PnPDevice 风格的 InstanceId filter
    await test_aqs(
        "VID_1EA7 PID_0064 in id",
        'System.PnP.InstanceId:="USB\\VID_1EA7&PID_0064*"',
    )

    # 测试 5: 用 SetupDi 风格的 container id
    await test_aqs(
        "HIDClass + Vendor + Product decimal",
        'System.Devices.InterfaceClassGuid:="{4D1E55B2-F16F-11CF-88CB-001111000030}" '
        'AND System.DeviceInterface.Hid.VendorId:=7847 '  # 0x1EA7
        'AND System.DeviceInterface.Hid.ProductId:=100',  # 0x64
    )


if __name__ == "__main__":
    asyncio.run(main())
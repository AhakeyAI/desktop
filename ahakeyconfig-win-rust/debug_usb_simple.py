#!/usr/bin/env python3
"""快速验证 AhaKey USB AQS 过滤器"""
import asyncio
from winrt.windows.devices.enumeration import DeviceInformation


async def main():
    tests = [
        ("AQS HIDClass + VID 1EA7 + PID 64",
         'System.Devices.InterfaceClassGuid:="{4D1E55B2-F16F-11CF-88CB-001111000030}" '
         'AND System.DeviceInterface.Hid.VendorId:=0x1EA7 '
         'AND System.DeviceInterface.Hid.ProductId:=0x64'),
        ("AQS VID/PID only decimal",
         'System.DeviceInterface.Hid.VendorId:=7847 '
         'AND System.DeviceInterface.Hid.ProductId:=100'),
        ("AQS PnP InstanceId match",
         'System.PnP.InstanceId:="USB\\VID_1EA7&PID_0064*"'),
        ("AQS DeviceDescription",
         'System.ItemNameDisplay:LIKE="*AhaKey*"'),
        ("AQS VID 1EA7 only",
         'System.DeviceInterface.Hid.VendorId:=0x1EA7'),
        ("AQS VID 30C9 PID 0057 (Integrated Camera)",
         'System.DeviceInterface.Hid.VendorId:=0x30C9 '
         'AND System.DeviceInterface.Hid.ProductId:=0x0057'),
    ]

    for name, aqs in tests:
        try:
            col = await DeviceInformation.find_all_async_aqs_filter(aqs)
            print(f"{name}: {col.size} devices")
            for i in range(min(col.size, 5)):
                print(f"  - {col[i].name} | {col[i].id}")
        except Exception as e:
            print(f"{name}: ERROR {e}")


if __name__ == "__main__":
    asyncio.run(main())
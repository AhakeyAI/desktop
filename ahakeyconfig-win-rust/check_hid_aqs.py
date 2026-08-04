#!/usr/bin/env python3
"""
列举所有 VID 0x1EA7 以外的 HID 设备,看有没有疑似 AhaKey 的
"""
import asyncio
import os
from winrt.windows.devices.enumeration import DeviceInformation
from winrt.windows.foundation import IPropertyValue


async def main():
    aqs = 'System.Devices.InterfaceClassGuid:="{4D1E55B2-F16F-11CF-88CB-001111000030}"'
    col = await DeviceInformation.find_all_async_aqs_filter(aqs)
    print(f"Total HID devices: {col.size}")

    skip = ["Mouse", "Keyboard", "Touchpad", "Receiver", "TrackPad",
            "Consumer", "I2C", "ConvertedDevice", "Compatible",
            "DESKTOP", "INTC", "INTEGRATED", "WebCam", "Camera",
            "Audio", "Sensor", "Button", "Wake", "Compliance",
            "Vendor-defined", "Generic Desktop", "Vendor Defined",
            "Mic", "Gaming", "RGB"]

    print(f"\n--- Devices with non-standard names ---")
    for i in range(col.size):
        info = col[i]
        name = info.name or ""
        if any(s.lower() in name.lower() for s in skip):
            continue
        if not name:
            continue
        print(f"  - '{name}'")
        print(f"    {info.id}")


if __name__ == "__main__":
    asyncio.run(main())
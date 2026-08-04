#!/usr/bin/env python3
"""
用 HID 设备 ID 打开 AhaKey 5A93:
\\?\HID#{00001812-0000-1000-8000-00805f9b34fb}_Dev_VID&0107d7_PID&0000_REV&0110_dc045a93df2c#9&33faea76&0&0000#{4d1e55b2-f16f-11cf-88cb-001111000030}\KBD
"""
import asyncio
from winrt.windows.devices.humaninterfacedevice import HidDevice
from winrt.windows.storage.streams import DataWriter, Buffer


async def main():
    device_id = r"\\?\HID#{00001812-0000-1000-8000-00805f9b34fb}_Dev_VID&0107d7_PID&0000_REV&0110_dc045a93df2c#9&33faea76&0&0000#{4d1e55b2-f16f-11cf-88cb-001111000030}\KBD"
    print(f"[test] opening HidDevice: {device_id}")

    op = HidDevice.from_id_async(device_id)
    device = op.get_results()
    if not device:
        print("[test] ✗ HidDevice is None")
        return

    print(f"[test] ✓ HidDevice opened!")
    print(f"[test]   product_id={device.product_id}")
    print(f"[test]   vendor_id={device.vendor_id}")
    print(f"[test]   version_number={device.version_number}")
    print(f"[test]   usage_page={device.usage_page}")
    print(f"[test]   usage_id={device.usage_id}")

    # 获取 input/output reports
    print("[test] getting input reports...")
    try:
        input_reports = device.get_input_report_descriptors()
        print(f"[test]   input reports count={input_reports.size if input_reports else 0}")
        if input_reports:
            for i in range(input_reports.size):
                r = input_reports[i]
                print(f"[test]     report {i}: id={r.report_id} len={r.report_length}")
    except Exception as e:
        print(f"[test]   input reports error: {e}")


if __name__ == "__main__":
    asyncio.run(main())
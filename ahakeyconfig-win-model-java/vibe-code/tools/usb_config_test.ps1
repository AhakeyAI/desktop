param(
    [ValidateSet("List", "Effect", "Brightness", "State", "Query", "Sequence")]
    [string]$Command = "Sequence",
    [int]$Value = 2
)

$ErrorActionPreference = "Stop"

$source = @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class AhaKeyHid {
    private const int DIGCF_PRESENT = 0x00000002;
    private const int DIGCF_DEVICEINTERFACE = 0x00000010;
    private const uint GENERIC_READ = 0x80000000;
    private const uint GENERIC_WRITE = 0x40000000;
    private const uint FILE_SHARE_READ = 0x00000001;
    private const uint FILE_SHARE_WRITE = 0x00000002;
    private const uint OPEN_EXISTING = 3;

    [StructLayout(LayoutKind.Sequential)]
    private struct SP_DEVICE_INTERFACE_DATA {
        public int cbSize;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct SP_DEVICE_INTERFACE_DETAIL_DATA {
        public int cbSize;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 512)]
        public string DevicePath;
    }

    [DllImport("hid.dll")]
    private static extern void HidD_GetHidGuid(out Guid HidGuid);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern IntPtr SetupDiGetClassDevs(ref Guid ClassGuid, IntPtr Enumerator, IntPtr hwndParent, int Flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiEnumDeviceInterfaces(IntPtr DeviceInfoSet, IntPtr DeviceInfoData, ref Guid InterfaceClassGuid, int MemberIndex, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData);

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr DeviceInfoSet, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData, ref SP_DEVICE_INTERFACE_DETAIL_DATA DeviceInterfaceDetailData, int DeviceInterfaceDetailDataSize, out int RequiredSize, IntPtr DeviceInfoData);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern IntPtr CreateFile(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool WriteFile(IntPtr hFile, byte[] lpBuffer, int nNumberOfBytesToWrite, out int lpNumberOfBytesWritten, IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    public static string[] ListDevicePaths() {
        Guid hidGuid;
        HidD_GetHidGuid(out hidGuid);
        IntPtr infoSet = SetupDiGetClassDevs(ref hidGuid, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        if (infoSet == IntPtr.Zero || infoSet.ToInt64() == -1) {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        var paths = new List<string>();
        try {
            for (int index = 0; ; index++) {
                var data = new SP_DEVICE_INTERFACE_DATA();
                data.cbSize = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
                if (!SetupDiEnumDeviceInterfaces(infoSet, IntPtr.Zero, ref hidGuid, index, ref data)) {
                    int err = Marshal.GetLastWin32Error();
                    if (err == 259) break;
                    throw new Win32Exception(err);
                }

                var detail = new SP_DEVICE_INTERFACE_DETAIL_DATA();
                detail.cbSize = IntPtr.Size == 8 ? 8 : 5;
                int required;
                if (SetupDiGetDeviceInterfaceDetail(infoSet, ref data, ref detail, Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DETAIL_DATA)), out required, IntPtr.Zero)) {
                    paths.Add(detail.DevicePath);
                }
            }
        } finally {
            SetupDiDestroyDeviceInfoList(infoSet);
        }
        return paths.ToArray();
    }

    public static string FindAhaKeyVendorPath() {
        foreach (string path in ListDevicePaths()) {
            string p = path.ToLowerInvariant();
            if (p.Contains("vid_413c") && p.Contains("pid_2107") && (p.Contains("mi_01") || p.Contains("col02"))) {
                return path;
            }
        }
        foreach (string path in ListDevicePaths()) {
            string p = path.ToLowerInvariant();
            if (p.Contains("vid_413c") && p.Contains("pid_2107")) {
                return path;
            }
        }
        return null;
    }

    public static int Send(string path, byte[] payload) {
        IntPtr handle = CreateFile(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (handle == IntPtr.Zero || handle.ToInt64() == -1) {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        try {
            byte[] report65 = new byte[65];
            report65[0] = 0;
            Array.Copy(payload, 0, report65, 1, Math.Min(payload.Length, 64));
            int written;
            if (WriteFile(handle, report65, report65.Length, out written, IntPtr.Zero)) {
                return written;
            }

            byte[] report64 = new byte[64];
            Array.Copy(payload, 0, report64, 0, Math.Min(payload.Length, 64));
            if (WriteFile(handle, report64, report64.Length, out written, IntPtr.Zero)) {
                return written;
            }
            throw new Win32Exception(Marshal.GetLastWin32Error());
        } finally {
            CloseHandle(handle);
        }
    }
}
"@

Add-Type -TypeDefinition $source

function New-Frame([byte[]]$Body) {
    $frame = New-Object byte[] (4 + $Body.Length)
    $frame[0] = 0xAA
    $frame[1] = 0xBB
    [Array]::Copy($Body, 0, $frame, 2, $Body.Length)
    $frame[$frame.Length - 2] = 0xCC
    $frame[$frame.Length - 1] = 0xDD
    return $frame
}

function New-UsbPacket([byte[]]$Frame) {
    $packet = New-Object byte[] 64
    $packet[0] = 0xA1
    $packet[1] = [byte]$Frame.Length
    [Array]::Copy($Frame, 0, $packet, 2, $Frame.Length)
    return $packet
}

function Send-DeviceFrame([byte[]]$Body) {
    $path = [AhaKeyHid]::FindAhaKeyVendorPath()
    if (-not $path) {
        throw "AhaKey USB HID device was not found. Confirm the keyboard shows HID."
    }
    $frame = New-Frame $Body
    $packet = New-UsbPacket $frame
    $written = [AhaKeyHid]::Send($path, $packet)
    Write-Host ("Sent {0} bytes to {1}" -f $written, $path)
    Write-Host ("Frame: " + (($frame | ForEach-Object { $_.ToString("X2") }) -join "-"))
}

if ($Command -eq "List") {
    [AhaKeyHid]::ListDevicePaths() | Where-Object { $_.ToLowerInvariant().Contains("vid_413c") -or $_.ToLowerInvariant().Contains("pid_2107") }
    exit 0
}

switch ($Command) {
    "Effect" {
        Send-DeviceFrame ([byte[]](0x91, [byte]$Value))
    }
    "Brightness" {
        Send-DeviceFrame ([byte[]](0x85, [byte]$Value))
    }
    "State" {
        Send-DeviceFrame ([byte[]](0x90, [byte]$Value))
    }
    "Query" {
        Send-DeviceFrame ([byte[]](0x00))
    }
    "Sequence" {
        Send-DeviceFrame ([byte[]](0x85, 35))
        Start-Sleep -Milliseconds 500
        Send-DeviceFrame ([byte[]](0x91, 2))
        Start-Sleep -Seconds 2
        Send-DeviceFrame ([byte[]](0x91, 5))
        Start-Sleep -Seconds 2
        Send-DeviceFrame ([byte[]](0x90, 1))
    }
}

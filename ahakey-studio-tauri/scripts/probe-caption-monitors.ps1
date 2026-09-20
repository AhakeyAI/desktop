[CmdletBinding()]
param([switch]$OpenTestWindows)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class AhaKeyMonitorProbe {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct INFO { public uint Size; public RECT Monitor, Work; public uint Flags; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; }
  [StructLayout(LayoutKind.Sequential)] public struct MSG { public IntPtr Window; public uint Message; public UIntPtr WParam; public IntPtr LParam; public uint Time; public POINT Point; public uint Private; }
  public delegate bool MonitorCallback(IntPtr monitor, IntPtr dc, ref RECT rect, IntPtr data);
  [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
  [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc,IntPtr rect,MonitorCallback callback,IntPtr data);
  [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr monitor,ref INFO info);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr CreateWindowEx(uint ex,string cls,string title,uint style,int x,int y,int width,int height,IntPtr parent,IntPtr menu,IntPtr instance,IntPtr param);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window,int command);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern bool DestroyWindow(IntPtr window);
  [DllImport("user32.dll")] static extern bool PeekMessage(out MSG msg,IntPtr window,uint first,uint last,uint remove);
  [DllImport("user32.dll")] static extern bool TranslateMessage(ref MSG msg);
  [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref MSG msg);
  public static INFO[] Monitors() {
    var result=new List<INFO>(); MonitorCallback callback=delegate(IntPtr monitor,IntPtr dc,ref RECT rect,IntPtr data) {
      var info=new INFO { Size=(uint)Marshal.SizeOf(typeof(INFO)) };if(GetMonitorInfo(monitor,ref info))result.Add(info);return true;
    };EnumDisplayMonitors(IntPtr.Zero,IntPtr.Zero,callback,IntPtr.Zero);return result.ToArray();
  }
  public static IntPtr Open(INFO info,int index) {
    var window=CreateWindowEx(0,"STATIC","AhaKey monitor probe "+index,0x00CF0000,info.Work.Left+60,info.Work.Top+60,300,140,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero);
    if(window==IntPtr.Zero)throw new Exception("Cannot create monitor probe window");ShowWindow(window,4);return window;
  }
  public static void Pump() { MSG msg;while(PeekMessage(out msg,IntPtr.Zero,0,0,1)){TranslateMessage(ref msg);DispatchMessage(ref msg);} }
}
'@
$priorContext = [AhaKeyMonitorProbe]::SetThreadDpiAwarenessContext([IntPtr](-4))
$windows = [System.Collections.Generic.List[IntPtr]]::new()
try {
    $index=0
    $observations=@(foreach($monitor in [AhaKeyMonitorProbe]::Monitors()) {
        $index++
        $window=if($OpenTestWindows){[AhaKeyMonitorProbe]::Open($monitor,$index)}else{[IntPtr]::Zero}
        if($window -ne [IntPtr]::Zero){$windows.Add($window)}
        [pscustomobject]@{index=$index;window=$window.ToInt64();left=$monitor.Work.Left;top=$monitor.Work.Top;right=$monitor.Work.Right;bottom=$monitor.Work.Bottom;primary=($monitor.Flags -band 1)-ne 0}
    })
    $observations | ConvertTo-Json -Compress
    # The caller closes only these disposable windows after its placement checks.
    while(@($windows | Where-Object {[AhaKeyMonitorProbe]::IsWindow($_)}).Count -gt 0) {
        [AhaKeyMonitorProbe]::Pump()
        Start-Sleep -Milliseconds 20
    }
} finally {
    foreach($window in $windows){if([AhaKeyMonitorProbe]::IsWindow($window)){[AhaKeyMonitorProbe]::DestroyWindow($window)|Out-Null}}
    [AhaKeyMonitorProbe]::SetThreadDpiAwarenessContext($priorContext)|Out-Null
}

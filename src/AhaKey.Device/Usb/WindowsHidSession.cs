using System.Collections.Immutable;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;
using AhaKey.Protocol;
namespace AhaKey.Device.Usb;

public sealed class WindowsHidSessionFactory(bool displayCharacterization = false,bool defaultBindings=false) : IWindowsHidSessionFactory
{
    private readonly DisplayCharacterizationGuard? characterization=displayCharacterization||defaultBindings?new(defaultBindings):null;
    public Task<IReadOnlyList<HidCandidate>> EnumerateAsync(CancellationToken ct) => Task.Run(() => HidNative.Enumerate(ct), ct);
    public IWindowsHidSession Create(Guid id) => new WindowsHidSession(id,characterization);
}

// All native resources are instance-owned. Reader and writes settle before handles are released.
public sealed class WindowsHidSession(Guid id,DisplayCharacterizationGuard? characterization=null) : IWindowsHidSession
{
    private readonly CancellationTokenSource lifetime = new();
    private readonly SemaphoreSlim writes = new(1, 1);
    private SafeFileHandle? read, write;
    private Task reader = Task.CompletedTask;
    private Task? close;
    private readonly object sync = new();
    public Guid Id => id;
    public bool ReaderRunning { get; private set; }
    public async Task OpenAsync(HidCandidate candidate, Action<HidInput> input, Action<Guid,Exception> failed, CancellationToken ct)
    {
        HidSelectionPolicy.Require(candidate); ct.ThrowIfCancellationRequested();
        // Re-enumerate before opening I/O: unplug/replug or another matching device must not bypass selection.
        var selection = HidSelectionPolicy.Select(await Task.Run(() => HidNative.Enumerate(ct), ct));
        if (selection.Candidate is not {} current || current.Path != candidate.Path)
            throw new UsbException(selection.ErrorKey ?? "UsbUnidentified", "USB selection changed before open.");
        read = HidNative.Open(candidate.Path, 0x80000000, true);
        try { write = HidNative.Open(candidate.Path, 0x40000000, true); }
        catch { read.Dispose(); read = null; throw; }
        ReaderRunning = true;
        reader = Task.Run(async () =>
        {
            try
            {
                while (!lifetime.IsCancellationRequested)
                {
                    var buffer = new byte[current.InputLength];
                    var result = await HidNative.IoAsync(read, buffer, false, lifetime.Token);
                    if (!result.Success) throw new UsbException("UsbReadFailed", $"ReadFile error {result.Error}.");
                    if (result.BytesWritten < 1 || result.BytesWritten > buffer.Length) throw new UsbException("UsbReadFailed", "Invalid native read size.");
                    input(new(Id, DateTimeOffset.UtcNow, buffer.Take(result.BytesWritten).ToImmutableArray()));
                }
            }
            catch (Exception ex) when (lifetime.IsCancellationRequested && ex is OperationCanceledException or UsbException) { }
            catch (Exception ex) { failed(Id, ex); }
            finally { ReaderRunning = false; }
        });
    }
    public async Task<HidWriteResult> WriteAsync(ImmutableArray<byte> report, CancellationToken ct)
    {
        if (!(characterization is null?UsbReportCodec.IsAllowedReport(report.AsSpan()):characterization.IsApprovedReport(report.AsSpan()))) throw new UsbException("UsbReadOnly", "Report outside the selected read-only scope.");
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(ct, lifetime.Token);
        await writes.WaitAsync(linked.Token);
        try { characterization?.Consume(report.AsSpan());return await HidNative.IoAsync(write ?? throw new UsbException("UsbNotReady", "No USB handle."), report.ToArray(), true, linked.Token); }
        finally { writes.Release(); }
    }
    public async Task<HidWriteResult> WriteConfigAsync(ApprovedConfigRead query,CancellationToken ct)
    {
        using var linked=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime.Token);await writes.WaitAsync(linked.Token);
        try{linked.Token.ThrowIfCancellationRequested();query.Consume(Id);return await HidNative.IoAsync(write??throw new UsbException("UsbNotReady","No USB handle."),query.Report.ToArray(),true,linked.Token);}
        finally{writes.Release();}
    }
    public async Task<HidWriteResult> WriteControlAsync(ApprovedControl control,CancellationToken ct)
    {
        using var linked=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime.Token);
        await writes.WaitAsync(linked.Token);
        try
        {
            linked.Token.ThrowIfCancellationRequested();control.Consume(Id,control.Command.Frame.AsSpan());
            return await HidNative.IoAsync(write??throw new UsbException("UsbNotReady","No USB handle."),control.Command.UsbReport().ToArray(),true,linked.Token);
        }
        finally{writes.Release();}
    }
    public async Task<HidWriteResult> WriteDisplayAsync(ApprovedDisplayReport report,CancellationToken ct)
    {
        using var linked=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime.Token);
        await writes.WaitAsync(linked.Token);
        try {linked.Token.ThrowIfCancellationRequested();report.Consume(Id);return await HidNative.IoAsync(write??throw new UsbException("UsbNotReady","No USB handle."),report.Report.ToArray(),true,linked.Token);}
        finally{writes.Release();}
    }
    public void Cancel() { lock(sync) { if (close?.IsCompleted != true) lifetime.Cancel(); } }
    public ValueTask DisposeAsync() { lock(sync) return new(close ??= CloseAsync()); }
    private async Task CloseAsync()
    {
        lifetime.Cancel();
        await reader.ConfigureAwait(false);
        await writes.WaitAsync().ConfigureAwait(false);
        try { read?.Dispose(); write?.Dispose(); read = write = null; ReaderRunning = false; }
        finally { writes.Release(); }
        // CTS is retained until this session is collected so concurrent Cancel remains idempotent.
    }
}

internal static class HidNative
{
    [StructLayout(LayoutKind.Sequential)] internal struct InterfaceData { public int Size; public Guid Class; public int Flags; public UIntPtr Reserved; }
    [StructLayout(LayoutKind.Sequential)] internal struct DeviceData { public int Size; public Guid Class; public int DevInst; public UIntPtr Reserved; }
    [StructLayout(LayoutKind.Sequential)] internal struct Attributes { public int Size; public ushort Vid, Pid, Version; }
    [StructLayout(LayoutKind.Sequential)] internal struct Caps { [MarshalAs(UnmanagedType.ByValArray, SizeConst=32)] public ushort[] Words; }
    [StructLayout(LayoutKind.Sequential)] internal struct OverlappedData { public UIntPtr Internal, InternalHigh; public uint Offset, OffsetHigh; public IntPtr Event; }
    [DllImport("hid.dll")] private static extern void HidD_GetHidGuid(out Guid guid);
    [DllImport("hid.dll")] [return: MarshalAs(UnmanagedType.U1)] private static extern bool HidD_GetAttributes(SafeFileHandle h, ref Attributes attrs);
    [DllImport("hid.dll")] [return: MarshalAs(UnmanagedType.U1)] private static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr data);
    [DllImport("hid.dll")] [return: MarshalAs(UnmanagedType.U1)] private static extern bool HidD_FreePreparsedData(IntPtr data);
    [DllImport("hid.dll")] private static extern int HidP_GetCaps(IntPtr data, out Caps caps);
    [DllImport("hid.dll")] private static extern int HidP_GetValueCaps(int type, IntPtr caps, ref ushort count, IntPtr data);
    [DllImport("hid.dll")] private static extern int HidP_GetButtonCaps(int type, IntPtr caps, ref ushort count, IntPtr data);
    [DllImport("hid.dll")] [return: MarshalAs(UnmanagedType.U1)] private static extern bool HidD_GetManufacturerString(SafeFileHandle h, byte[] text, int length);
    [DllImport("hid.dll")] [return: MarshalAs(UnmanagedType.U1)] private static extern bool HidD_GetProductString(SafeFileHandle h, byte[] text, int length);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern IntPtr SetupDiGetClassDevsW(ref Guid guid, string? enumerator, IntPtr parent, uint flags);
    [DllImport("setupapi.dll", SetLastError=true)] private static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr dev, ref Guid guid, uint index, ref InterfaceData data);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool SetupDiGetDeviceInterfaceDetailW(IntPtr set, ref InterfaceData data, IntPtr detail, uint size, out uint required, ref DeviceData device);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool SetupDiGetDeviceInstanceIdW(IntPtr set, ref DeviceData data, StringBuilder id, int size, out int required);
    [DllImport("setupapi.dll")] private static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern SafeFileHandle CreateFileW(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool ReadFile(SafeFileHandle handle, IntPtr buffer, int size, out int bytes, IntPtr overlapped);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool WriteFile(SafeFileHandle handle, IntPtr buffer, int size, out int bytes, IntPtr overlapped);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool GetOverlappedResult(SafeFileHandle handle, IntPtr overlapped, out int bytes, bool wait);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool CancelIoEx(SafeFileHandle handle, IntPtr overlapped);
    internal static SafeFileHandle Open(string path, uint access, bool overlapped)
    {
        var handle = CreateFileW(path, access, 3, IntPtr.Zero, 3, overlapped ? 0x40000000u : 0, IntPtr.Zero);
        if (!handle.IsInvalid) return handle;
        int error = Marshal.GetLastWin32Error(); handle.Dispose();
        throw new UsbException("UsbOpenFailed", $"CreateFile error {error}.");
    }
    internal static IReadOnlyList<HidCandidate> Enumerate(CancellationToken ct)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Windows HID required.");
        var result = new List<HidCandidate>(); HidD_GetHidGuid(out var guid);
        var set = SetupDiGetClassDevsW(ref guid, null, IntPtr.Zero, 0x12);
        if (set == new IntPtr(-1)) throw new UsbException("UsbEnumerationFailed", "SetupDiGetClassDevs failed.");
        try
        {
            for (uint i=0; ; i++)
            {
                ct.ThrowIfCancellationRequested(); var data = new InterfaceData { Size=Marshal.SizeOf<InterfaceData>() };
                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref guid, i, ref data))
                { if (Marshal.GetLastWin32Error() != 259) throw new UsbException("UsbEnumerationFailed", "Interface enumeration failed."); break; }
                var dev = new DeviceData { Size=Marshal.SizeOf<DeviceData>() };
                SetupDiGetDeviceInterfaceDetailW(set, ref data, IntPtr.Zero, 0, out var needed, ref dev);
                if (needed < 8 || needed > 65536) continue;
                var detail = Marshal.AllocHGlobal((int)needed);
                try
                {
                    Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                    if (!SetupDiGetDeviceInterfaceDetailW(set, ref data, detail, needed, out _, ref dev)) continue;
                    var path = Marshal.PtrToStringUni(detail+4) ?? "";
                    if (!path.Contains("vid_413c&pid_2107", StringComparison.OrdinalIgnoreCase)) continue;
                    var instance = new StringBuilder(1024);
                    SetupDiGetDeviceInstanceIdW(set, ref dev, instance, instance.Capacity, out _);
                    result.Add(Inspect(path, instance.ToString()));
                }
                finally { Marshal.FreeHGlobal(detail); }
            }
        }
        finally { SetupDiDestroyDeviceInfoList(set); }
        return result;
    }
    private static int? Part(string path, string part)
    { var m=Regex.Match(path, $@"(?:&|#){part}([0-9a-f]{{2}})(?:&|#)", RegexOptions.IgnoreCase); return m.Success ? Convert.ToInt32(m.Groups[1].Value,16) : null; }
    private static HidCandidate Inspect(string path, string instance)
    {
        var candidate = new HidCandidate(path, instance, 0x413C, 0x2107, Part(path,"mi_"), Part(path,"col"),0,0,0,0,0,[],[],null,null);
        try
        {
            using var h = Open(path,0,false); var attributes=new Attributes { Size=Marshal.SizeOf<Attributes>() };
            if (!HidD_GetAttributes(h,ref attributes) || !HidD_GetPreparsedData(h,out var data)) throw new UsbException("UsbUnidentified","HID metadata unavailable.");
            try
            {
                if (HidP_GetCaps(data,out var caps) != 0x110000) throw new UsbException("UsbUnidentified","HID capabilities unavailable.");
                var w=caps.Words;
                var manufacturer=new byte[512]; var product=new byte[512];
                string? SafeString(bool ok, byte[] raw) => ok ? new string(Encoding.Unicode.GetString(raw).TrimEnd('\0').Where(c=>!char.IsControl(c)).Take(120).ToArray()) : null;
                return candidate with { Vid=attributes.Vid, Pid=attributes.Pid, Usage=w[0], UsagePage=w[1], InputLength=w[2],OutputLength=w[3],FeatureLength=w[4],
                    InputIds=ReportIds(data,0,w[23],w[24]), OutputIds=ReportIds(data,1,w[26],w[27]),
                    Manufacturer=SafeString(HidD_GetManufacturerString(h,manufacturer,manufacturer.Length),manufacturer),
                    Product=SafeString(HidD_GetProductString(h,product,product.Length),product) };
            }
            finally { HidD_FreePreparsedData(data); }
        }
        catch (Exception ex) { return candidate with { InspectionError=ex is UsbException ? ex.Message : ex.GetType().Name }; }
    }
    private static ImmutableArray<byte> ReportIds(IntPtr data, int type, ushort buttons, ushort values)
    {
        var ids=new HashSet<byte>();
        foreach (bool button in new[] { true,false })
        {
            ushort count=button?buttons:values; if(count==0)continue;
            if(count>1024)throw new UsbException("UsbUnidentified","HID capability count exceeds limit.");
            var mem=Marshal.AllocHGlobal(72*count);
            try
            {
                int status=button?HidP_GetButtonCaps(type,mem,ref count,data):HidP_GetValueCaps(type,mem,ref count,data);
                if(status!=0x110000)throw new UsbException("UsbUnidentified","HID report IDs unavailable.");
                for(int j=0;j<count;j++)ids.Add(Marshal.ReadByte(mem,j*72+2));
            }
            finally { Marshal.FreeHGlobal(mem); }
        }
        return ids.Order().ToImmutableArray();
    }
    internal static Task<HidWriteResult> IoAsync(SafeFileHandle handle, byte[] buffer, bool writing, CancellationToken ct) => Task.Run(() =>
    {
        ct.ThrowIfCancellationRequested();
        using var done=new EventWaitHandle(false,EventResetMode.ManualReset);
        var ov=Marshal.AllocHGlobal(Marshal.SizeOf<OverlappedData>());
        var pinned=GCHandle.Alloc(buffer,GCHandleType.Pinned);
        try
        {
            Marshal.StructureToPtr(new OverlappedData { Event=done.SafeWaitHandle.DangerousGetHandle() },ov,false);
            int count;
            bool success=writing?WriteFile(handle,pinned.AddrOfPinnedObject(),buffer.Length,out count,ov):ReadFile(handle,pinned.AddrOfPinnedObject(),buffer.Length,out count,ov);
            int error=success?0:Marshal.GetLastWin32Error();
            if(!success && error!=997)return new HidWriteResult(false,count,error);
            // Cancellation targets this exact OVERLAPPED. Drain completion before freeing its storage/buffer.
            using var registration=ct.Register(()=>CancelIoEx(handle,ov));
            success=GetOverlappedResult(handle,ov,out count,true); error=success?0:Marshal.GetLastWin32Error();
            return new HidWriteResult(success,count,error);
        }
        finally { pinned.Free();Marshal.FreeHGlobal(ov); }
    },CancellationToken.None);
}

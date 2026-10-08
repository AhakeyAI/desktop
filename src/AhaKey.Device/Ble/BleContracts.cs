using System.Collections.Immutable;
namespace AhaKey.Device.Ble;
public enum BleStage { Disconnected, Discovering, AcquiringLink, DiscoveringGatt, Subscribing, ReadingStatus, ReadingCapabilities, Ready, Reconnecting, Disconnecting, Error }
public enum GattResultStatus { Success, Unreachable, ProtocolError, AccessDenied, Unknown }
[Flags] public enum GattFeatures { None=0, Read=1, Write=2, WriteWithoutResponse=4, Notify=8, Indicate=16 }
public sealed record BleDeviceInfo(string Id,string Name,string? Address);
public sealed record AdapterInfo(string? Name,string State);
public sealed record GattResult(GattResultStatus Status,byte? ProtocolError=null)
{
    public bool Success=>Status==GattResultStatus.Success;
    public void RequireSuccess(string operation) {if(!Success) throw new BleException("BleGattFailure",$"{operation}: {Status}; ATT={ProtocolError?.ToString("X2") ?? "unknown"}");}
}
public sealed record GattCharacteristicInfo(Guid Uuid,GattFeatures Properties);
public sealed record GattServiceInfo(Guid Uuid,ImmutableArray<GattCharacteristicInfo> Characteristics,GattResult Result);
public sealed record BleNotification(Guid SessionId,DateTimeOffset ArrivedAt,ImmutableArray<byte> Bytes);
public sealed class BleException(string key,string detail) : Exception(detail) { public string Key { get; }=key; }
public interface IWindowsGattSession : IAsyncDisposable
{
    Guid Id {get;}
    AdapterInfo Adapter {get;}
    bool NativeConnected {get;}
    GattResult? TeardownResult=>null;
    event Action<Guid,bool>? ConnectionChanged;
    Task<IReadOnlyList<BleDeviceInfo>> DiscoverAsync(TimeSpan duration,CancellationToken ct);
    Task AcquireAsync(string deviceId,CancellationToken ct);
    Task<ImmutableArray<GattServiceInfo>> DiscoverGattAsync(CancellationToken ct);
    Task<GattResult> SubscribeAsync(Guid service,Guid characteristic,Action<BleNotification> receiver,CancellationToken ct);
    Task<GattResult> WriteConfigAsync(Guid service,Guid characteristic,Usb.ApprovedConfigRead query,CancellationToken ct)=>throw new NotSupportedException();
    Task<GattResult> WriteControlAsync(Guid service,Guid characteristic,ApprovedControl control,CancellationToken ct) => throw new NotSupportedException("Physical controls unavailable in this session.");
    Task<GattResult> WriteCommandAsync(Guid service,Guid characteristic,ImmutableArray<byte> frame,CancellationToken ct);
}
public interface IWindowsGattSessionFactory { IWindowsGattSession Create(Guid id); }
// Exact identities are supplied only after observing the selected device's full Windows GATT catalog.
public sealed record GattContract(Guid Service,Guid Data,Guid Command,Guid Notify)
{
    // Confirmed by the selected AhaKey's Windows GATT inspection on 2026-09-20; see Phase 3 evidence.
    public static GattContract WindowsObserved {get;}=new(new("00007340-0000-1000-8000-00805f9b34fb"),new("00007341-0000-1000-8000-00805f9b34fb"),new("00007343-0000-1000-8000-00805f9b34fb"),new("00007344-0000-1000-8000-00805f9b34fb"));
    public void Validate(ImmutableArray<GattServiceInfo> catalog)
    {
        var services=catalog.Where(x=>x.Uuid==Service).ToArray();
        if(services.Length!=1) throw new BleException("BleUnsupportedGatt","Exact service UUID missing or ambiguous.");
        services[0].Result.RequireSuccess("Characteristics");var chars=services[0].Characteristics;
        foreach(var (uuid,feature) in new[]{(Data,GattFeatures.Write),(Command,GattFeatures.Write),(Notify,GattFeatures.Notify)})
        {var matches=chars.Where(x=>x.Uuid==uuid).ToArray();if(matches.Length!=1 || !matches[0].Properties.HasFlag(feature)) throw new BleException("BleUnsupportedGatt","Exact required characteristic or properties missing.");}
    }
}

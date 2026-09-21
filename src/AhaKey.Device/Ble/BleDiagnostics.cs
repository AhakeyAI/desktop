using System.Collections.Immutable;
using AhaKey.Protocol;
namespace AhaKey.Device.Ble;
public sealed record BleHistory(DateTimeOffset At,Guid? Session,string Event,string Detail);
public sealed record QueryEvidence(Guid SessionId,ReadOnlyQuery Command,DateTimeOffset WriteStartedAt,DateTimeOffset WriteCompletedAt,
    DateTimeOffset ResponseAt,ImmutableArray<byte> Tx,ImmutableArray<byte> Rx,GattResult Result)
{
    // Notifications can arrive before the native WriteWithResponse task completes.
    public double LatencyMs=>(ResponseAt-WriteStartedAt).TotalMilliseconds;
    public double ResponseAfterWriteCompletionMs=>(ResponseAt-WriteCompletedAt).TotalMilliseconds;
}
public sealed record BleDiagnostics
{
    public BleStage Stage {get;init;}=BleStage.Disconnected;
    public AdapterInfo Adapter {get;init;}=new(null,"Unknown");
    public BleDeviceInfo? Device {get;init;}
    public Guid? SessionId {get;init;}
    public bool? NativeConnected {get;init;}
    public bool Subscribed {get;init;}
    public bool IsLive {get;init;}
    public DateTimeOffset? ObservedAt {get;init;}
    public DateTimeOffset? LastDataAt {get;init;}
    public ImmutableArray<GattServiceInfo> Catalog {get;init;}=[];
    public PhysicalStatus? PhysicalStatus {get;init;}
    public PhysicalCapabilities? Capabilities {get;init;}
    public QueryEvidence? LastQuery {get;init;}
    public QueryEvidence? LastStatusQuery {get;init;}
    public ImmutableArray<byte> LastTx {get;init;}=[];
    public ImmutableArray<byte> LastRx {get;init;}=[];
    public GattResult? LastGattResult {get;init;}
    public GattResult? LastTeardownResult {get;init;}
    public string? Error {get;init;}
    public string? ErrorKey {get;init;}
    public int ReconnectAttempt {get;init;}
    public ImmutableArray<BleHistory> History {get;init;}=[];
}

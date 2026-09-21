using System.Collections.Immutable;
using AhaKey.Core;
using AhaKey.Device.Ble;
using AhaKey.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
namespace AhaKey.Device.Tests;

public sealed class FakeGattFactory : IWindowsGattSessionFactory
{
    public List<FakeGatt> Sessions {get;}=[];
    public Action<FakeGatt>? Configure {get;set;}
    public IWindowsGattSession Create(Guid id) {var s=new FakeGatt(id);Configure?.Invoke(s);Sessions.Add(s);return s;}
}
public sealed class FakeGatt(Guid id) : IWindowsGattSession
{
    public static readonly ImmutableArray<byte> StatusFrame=[0xAA,0xBB,0,91,0xDA,1,4,2,0,1,75,7,0xCC,0xDD];
    public static readonly ImmutableArray<byte> CapsFrame=[0xAA,0xBB,0x9F,0,3,2,1,4,1,0xFF,7,0,0,8,1,0xCC,0xDD];
    public Guid Id=>id;
    public AdapterInfo Adapter=>new("Fake","On");
    public bool NativeConnected=>!Disposed;
    public bool Disposed {get;private set;}
    public event Action<Guid,bool>? ConnectionChanged;
    public Action<BleNotification>? Receiver;
    public List<byte> Commands {get;}=[];
    public List<ImmutableArray<byte>> Controls {get;}=[];
    public Task<GattResult> WriteControlAsync(Guid service,Guid characteristic,ApprovedControl control,CancellationToken ct)
    {Assert.Equal(GattContract.WindowsObserved.Command,characteristic);control.Consume(Id,control.Command.Frame.AsSpan());Controls.Add(control.Command.Frame);if(Respond)Emit([0xAA,0xBB,control.Command.Opcode,0,0xCC,0xDD]);return Task.FromResult(WriteResult);}
    public Queue<GattResult> Subscriptions {get;}=new();
    public int SubscribeCount;
    public GattResult WriteResult=new(GattResultStatus.Success);
    public bool Respond=true;
    public ImmutableArray<byte> CapabilityResponse=CapsFrame;
    public Func<CancellationToken,Task>? Acquiring;
    public Func<CancellationToken,Task>? Discovering;
    public ImmutableArray<GattServiceInfo> Catalog=[new(GattContract.WindowsObserved.Service,[new(GattContract.WindowsObserved.Data,GattFeatures.Write),new(GattContract.WindowsObserved.Command,GattFeatures.Write),new(GattContract.WindowsObserved.Notify,GattFeatures.Notify)],new(GattResultStatus.Success))];
    public async Task<IReadOnlyList<BleDeviceInfo>> DiscoverAsync(TimeSpan duration,CancellationToken ct){if(Discovering is not null)await Discovering(ct);return [new("fake","Fake",null)];}
    public Task AcquireAsync(string deviceId,CancellationToken ct)=>Acquiring?.Invoke(ct)??Task.CompletedTask;
    public Task<ImmutableArray<GattServiceInfo>> DiscoverGattAsync(CancellationToken ct)=>Task.FromResult(Catalog);
    public Task<GattResult> SubscribeAsync(Guid service,Guid characteristic,Action<BleNotification> receiver,CancellationToken ct){SubscribeCount++;Receiver=receiver;return Task.FromResult(Subscriptions.Count>0?Subscriptions.Dequeue():new(GattResultStatus.Success));}
    public async Task<GattResult> WriteCommandAsync(Guid service,Guid characteristic,ImmutableArray<byte> frame,CancellationToken ct)
    {
        Assert.True(AhaKeyProtocol.IsAllowedQuery(frame.AsSpan()));Commands.Add(frame[2]);
        await Task.Delay(2,ct);
        // BLE notification may arrive before the managed awaited write continuation.
        if(Respond)Emit(frame[2]==0?StatusFrame:CapabilityResponse);
        return WriteResult;
    }
    public void Emit(ImmutableArray<byte> bytes,Guid? session=null)=>Receiver?.Invoke(new(session??Id,DateTimeOffset.UtcNow,bytes));
    public void LoseLink()=>ConnectionChanged?.Invoke(Id,false);
    public ValueTask DisposeAsync(){Disposed=true;return ValueTask.CompletedTask;}
}
public class BleTests
{
    private static BleTransport Transport(FakeGattFactory f)=>new(f,GattContract.WindowsObserved){QueryTimeout=TimeSpan.FromMilliseconds(100),RetryDelay=TimeSpan.Zero};
    private static BleDeviceInfo Selected=>new("fake","Fake",null);
    [Fact] public async Task ReadyRequiresBothQueriesAndNeverReadsConfiguration()
    {
        var f=new FakeGattFactory();await using var d=new RealAhaKeyDevice(Transport(f)){Selected=Selected};
        await d.ConnectAsync();Assert.True(d.Diagnostics.IsLive);Assert.Equal(91,d.Status.Battery);Assert.Equal(new byte[]{0,0x9F},f.Sessions.Single().Commands);
        Assert.False(d.Identity.IsSimulation);Assert.True(d.Diagnostics.Capabilities!.SupportedContract);
        await Assert.ThrowsAsync<BleException>(()=>d.WriteAsync(DeviceConfiguration.Default));await Assert.ThrowsAsync<BleException>(()=>d.ReadAsync());
        await d.DisconnectAsync();Assert.True(f.Sessions.Single().Disposed);Assert.False(d.Diagnostics.IsLive);Assert.Null(d.Status.Battery);
    }
    [Theory] [InlineData(GattResultStatus.AccessDenied)] [InlineData(GattResultStatus.ProtocolError)] [InlineData(GattResultStatus.Unreachable)]
    public async Task WriteFailureCannotPublishEvenIfNotificationArrived(GattResultStatus status)
    {
        var f=new FakeGattFactory{Configure=s=>s.WriteResult=new(status,5)};await using var t=Transport(f);await t.OpenAsync(Selected);
        await Assert.ThrowsAsync<BleException>(()=>t.QueryAsync(ReadOnlyQuery.PhysicalStatus));Assert.False(t.Diagnostics.IsLive);Assert.Equal(status,t.Diagnostics.LastGattResult!.Status);Assert.True(f.Sessions[0].Disposed);
    }
    [Fact] public async Task SubscriptionRetriesAreBoundedAndAwaited()
    {
        var f=new FakeGattFactory{Configure=s=>{for(int i=0;i<3;i++)s.Subscriptions.Enqueue(new(GattResultStatus.Unreachable));}};
        await using var t=Transport(f);await Assert.ThrowsAsync<BleException>(()=>t.OpenAsync(Selected));Assert.Equal(3,f.Sessions[0].SubscribeCount);Assert.True(f.Sessions[0].Disposed);Assert.Empty(f.Sessions[0].Commands);
    }
    [Fact] public async Task SubscriptionTransientFailureThenSuccess()
    {var f=new FakeGattFactory{Configure=s=>s.Subscriptions.Enqueue(new(GattResultStatus.Unreachable))};await using var t=Transport(f);await t.OpenAsync(Selected);Assert.True(t.Diagnostics.Subscribed);Assert.False(t.Diagnostics.IsLive);Assert.Equal(2,f.Sessions[0].SubscribeCount);}
    [Fact] public async Task PermanentSubscriptionFailureDoesNotRetry()
    {var f=new FakeGattFactory{Configure=s=>s.Subscriptions.Enqueue(new(GattResultStatus.ProtocolError,3))};await using var t=Transport(f);await Assert.ThrowsAsync<BleException>(()=>t.OpenAsync(Selected));Assert.Equal(1,f.Sessions[0].SubscribeCount);}
    [Theory] [InlineData(0)] [InlineData(1)] [InlineData(2)] [InlineData(3)]
    public async Task ExactGattContractRejectsMissingWrongAndFailedCharacteristics(int kind)
    {
        var f=new FakeGattFactory{Configure=s=>s.Catalog=kind switch{
            0=>[],1=>[s.Catalog[0] with{Characteristics=s.Catalog[0].Characteristics.RemoveAt(2)}],
            2=>[s.Catalog[0] with{Uuid=new("12347340-0000-1000-8000-00805f9b34fb")}],
            _=>[s.Catalog[0] with{Result=new(GattResultStatus.Unreachable)}]}};
        await using var t=Transport(f);await Assert.ThrowsAsync<BleException>(()=>t.OpenAsync(Selected));Assert.True(f.Sessions[0].Disposed);Assert.Equal(0,f.Sessions[0].SubscribeCount);
    }
    [Fact] public async Task CancelConnectionDisposesNativeSession()
    {
        var entered=new TaskCompletionSource();var f=new FakeGattFactory{Configure=s=>s.Acquiring=async ct=>{entered.SetResult();await Task.Delay(Timeout.Infinite,ct);}};
        await using var t=Transport(f);var connecting=t.OpenAsync(Selected);await entered.Task;var close=t.DisconnectAsync();await Assert.ThrowsAnyAsync<OperationCanceledException>(()=>connecting);await close;Assert.True(f.Sessions[0].Disposed);
    }
    [Fact] public async Task StaleDiscoveryCannotPublishAfterNewGeneration()
    {
        var release=new TaskCompletionSource();var f=new FakeGattFactory{Configure=s=>s.Discovering=_=>release.Task};await using var t=Transport(f);
        var old=t.DiscoverAsync();f.Configure=null;await t.DiscoverAsync();release.SetResult();await Assert.ThrowsAnyAsync<OperationCanceledException>(()=>old);Assert.Equal(BleStage.Disconnected,t.Diagnostics.Stage);Assert.All(f.Sessions,s=>Assert.True(s.Disposed));
    }
    [Fact] public async Task QuerySerializationAndOldSessionRejection()
    {
        var f=new FakeGattFactory();await using var t=Transport(f);await t.OpenAsync(Selected);var old=f.Sessions[0];
        await Task.WhenAll(t.QueryAsync(ReadOnlyQuery.PhysicalStatus),t.QueryAsync(ReadOnlyQuery.Capabilities));Assert.Equal(new byte[]{0,0x9F},old.Commands);
        await t.OpenAsync(Selected);Assert.True(old.Disposed);var before=t.Diagnostics;old.Emit(FakeGatt.StatusFrame);Assert.Equal(before,t.Diagnostics);
        var current=f.Sessions[1];current.Emit(FakeGatt.StatusFrame,old.Id);Assert.Equal(before,t.Diagnostics);
    }
    [Fact] public async Task WrongResponseAndTimeoutQuarantineSession()
    {
        var f=new FakeGattFactory{Configure=s=>s.Respond=false};await using var t=Transport(f);await t.OpenAsync(Selected);
        var request=t.QueryAsync(ReadOnlyQuery.PhysicalStatus);f.Sessions[0].Emit(FakeGatt.CapsFrame);await Assert.ThrowsAsync<BleException>(()=>request);Assert.True(f.Sessions[0].Disposed);Assert.Equal("BleQueryTimeout",t.Diagnostics.ErrorKey);
    }
    [Fact] public async Task ReconnectIsBoundedAndDisposesEveryFailedSession()
    {
        var f=new FakeGattFactory{Configure=s=>s.Acquiring=_=>throw new BleException("BleAdapterUnavailable","Off")};await using var d=new RealAhaKeyDevice(Transport(f)){Selected=Selected};
        await Assert.ThrowsAsync<BleException>(()=>d.ReconnectAsync());Assert.Equal(2,f.Sessions.Count);Assert.All(f.Sessions,s=>Assert.True(s.Disposed));Assert.Equal(2,d.Diagnostics.ReconnectAttempt);
    }
    [Fact] public async Task NativeLossClearsLiveStateAndTearsDown()
    {
        var f=new FakeGattFactory();await using var d=new RealAhaKeyDevice(Transport(f)){Selected=Selected};await d.ConnectAsync();f.Sessions[0].LoseLink();
        for(int i=0;i<50 && !f.Sessions[0].Disposed;i++)await Task.Delay(5);
        Assert.True(f.Sessions[0].Disposed);Assert.False(d.Diagnostics.IsLive);await d.ReconnectAsync();Assert.True(d.Diagnostics.IsLive);Assert.Equal(2,f.Sessions.Count);
    }
    [Fact] public async Task ManagerRealNeverFallsBackOrMarksDraftSynced()
    {
        var f=new FakeGattFactory();await using var d=new RealAhaKeyDevice(Transport(f)){Selected=Selected};var mock=new MockAhaKeyDevice{Latency=TimeSpan.Zero};using var m=new DeviceManager(mock,new(),NullLogger<DeviceManager>.Instance,d);
        await m.SelectBackendAsync(true);await m.ConnectAsync();Assert.Same(d,m.Device);Assert.Equal(ConnectionState.Connected,m.State);Assert.Null(m.Tracker.LastDeviceRead);Assert.NotEqual(SyncState.Synced,m.Tracker.State);
        await m.WriteAsync();Assert.Equal("BleReadOnly",m.ErrorKey);Assert.Null(mock.Status.SessionId);Assert.Equal(new byte[]{0,0x9F},f.Sessions[0].Commands);
    }
    [Fact] public async Task EveryOtherCommandIsBlockedBeforeNativeIo()
    {var f=new FakeGattFactory();await using var t=Transport(f);await t.OpenAsync(Selected);for(int c=0;c<256;c++)if(c!=0 && c!=0x9F)await Assert.ThrowsAsync<ArgumentOutOfRangeException>(()=>t.QueryAsync((ReadOnlyQuery)c));Assert.Empty(f.Sessions[0].Commands);}
    [Fact] public async Task ObservedEmptyCapabilitiesStillAllowsReadOnlyTelemetry()
    {
        var f=new FakeGattFactory{Configure=s=>s.CapabilityResponse=[0xAA,0xBB,0x9F,0,0xCC,0xDD]};await using var d=new RealAhaKeyDevice(Transport(f)){Selected=Selected};
        await d.ConnectAsync();Assert.True(d.Diagnostics.IsLive);Assert.False(d.Diagnostics.Capabilities!.SupportedContract);Assert.Null(d.Diagnostics.Capabilities.Bits);Assert.Equal("1.4",d.Identity.Firmware);
    }
    [Fact] public async Task MalformedCapabilitiesClosesSessionWithoutFurtherQueries()
    {
        var f=new FakeGattFactory{Configure=s=>s.CapabilityResponse=[0xAA,0xBB,0x9F,1,0xCC,0xDD]};await using var d=new RealAhaKeyDevice(Transport(f)){Selected=Selected};
        await Assert.ThrowsAsync<FormatException>(()=>d.ConnectAsync());Assert.True(f.Sessions[0].Disposed);Assert.False(d.Diagnostics.IsLive);Assert.Equal(2,f.Sessions[0].Commands.Count);
    }
    [Fact] public async Task OldParsedStatusCannotOverwriteNewSession()
    {
        var f=new FakeGattFactory();await using var t=Transport(f);await t.OpenAsync(Selected);var q=await t.QueryAsync(ReadOnlyQuery.PhysicalStatus);await t.OpenAsync(Selected);
        t.PublishStatus(q,AhaKeyProtocol.DecodeStatus(q.Rx.AsSpan()));t.PublishCapabilities(q,AhaKeyProtocol.DecodeCapabilities(FakeGatt.CapsFrame.AsSpan()));Assert.Null(t.Diagnostics.PhysicalStatus);Assert.False(t.Diagnostics.IsLive);
    }
    [Fact] public async Task DisconnectWaitsForManagerConnectionCancellation()
    {
        var entered=new TaskCompletionSource();var f=new FakeGattFactory{Configure=s=>s.Acquiring=async ct=>{entered.SetResult();await Task.Delay(Timeout.Infinite,ct);}};
        await using var d=new RealAhaKeyDevice(Transport(f)){Selected=Selected};using var m=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,d);await m.SelectBackendAsync(true);
        var connecting=m.ConnectAsync();await entered.Task;await m.DisconnectAsync();await connecting;Assert.Equal(ConnectionState.Disconnected,m.State);Assert.True(f.Sessions[0].Disposed);
    }
    [Fact] public async Task BackendSwitchCancelsConnectionWithoutMockAutoConnect()
    {
        var entered=new TaskCompletionSource();var f=new FakeGattFactory{Configure=s=>s.Acquiring=async ct=>{entered.SetResult();await Task.Delay(Timeout.Infinite,ct);}};
        await using var d=new RealAhaKeyDevice(Transport(f)){Selected=Selected};var mock=new MockAhaKeyDevice();using var m=new DeviceManager(mock,new(),NullLogger<DeviceManager>.Instance,d);await m.SelectBackendAsync(true);
        var connecting=m.ConnectAsync();await entered.Task;await m.SelectBackendAsync(false);await connecting;Assert.False(m.RealBackendSelected);Assert.Null(mock.Status.SessionId);Assert.True(f.Sessions[0].Disposed);
    }
    [Fact] public async Task DiagnosticHistoryIsBoundedAndExportRedactsIdentity()
    {
        var f=new FakeGattFactory();await using var t=Transport(f);await t.OpenAsync(new("secret-id","secret-name","secret-address"));for(int i=0;i<40;i++)await t.QueryAsync(ReadOnlyQuery.PhysicalStatus);
        Assert.Equal(64,t.Diagnostics.History.Length);var export=BleDiagnosticExport.Redacted(t.Diagnostics);Assert.DoesNotContain("secret",export);Assert.DoesNotContain("Fake",export);Assert.Contains(GattContract.WindowsObserved.Service.ToString(),export);
    }
    [Fact] public void WrongCharacteristicPropertiesCannotPassExactUuidCheck()
    {
        var s=new FakeGatt(Guid.NewGuid());var c=s.Catalog[0];var bad=c with{Characteristics=c.Characteristics.SetItem(2,new(GattContract.WindowsObserved.Notify,GattFeatures.Read))};
        Assert.Throws<BleException>(()=>GattContract.WindowsObserved.Validate([bad]));
    }
}

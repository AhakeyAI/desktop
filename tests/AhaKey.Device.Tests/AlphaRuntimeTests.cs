using AhaKey.Core;
using AhaKey.Device.Ble;
using Microsoft.Extensions.Logging.Abstractions;
namespace AhaKey.Device.Tests;

public sealed class AlphaRuntimeTests
{
    [Fact] public void QueryLatencyStartsAtTxEvenWhenNotificationPrecedesGattCompletion()
    {
        var start=DateTimeOffset.UtcNow;
        var q=new QueryEvidence(Guid.NewGuid(),AhaKey.Protocol.ReadOnlyQuery.Capabilities,start,start.AddMilliseconds(60),start.AddMilliseconds(20),[],[],new(GattResultStatus.Success));
        Assert.Equal(20,q.LatencyMs);Assert.Equal(-40,q.ResponseAfterWriteCompletionMs);
    }
    [Fact] public void CopiedDiagnosticsRedactIdentifiersEvenInsideFailureText()
    {var d=new BleDiagnostics{Device=new("private-windows-id","AhaKey","private-address"),Error="Failed private-windows-id",History=[new(DateTimeOffset.UtcNow,null,"Error","private-address unavailable")]};var text=BleDiagnosticExport.Redacted(d);Assert.DoesNotContain("private-windows-id",text);Assert.DoesNotContain("private-address",text);}
    private static RealAhaKeyDevice Device(FakeGattFactory factory)=>new(new(factory,GattContract.WindowsObserved){QueryTimeout=TimeSpan.FromMilliseconds(150),NativeTimeout=TimeSpan.FromMilliseconds(200),RetryDelay=TimeSpan.Zero});
    private static DeviceManager Manager(RealAhaKeyDevice real)=>new(new MockAhaKeyDevice{Latency=TimeSpan.Zero},new(),NullLogger<DeviceManager>.Instance,real);
    private static async Task Until(Func<bool> condition){for(int n=0;n<200 && !condition();n++)await Task.Delay(10);Assert.True(condition());}
    [Fact] public async Task FirstRunNeverDiscoversOrConnectsWithoutSelection()
    {
        var f=new FakeGattFactory();await using var real=Device(f);using var m=Manager(real);using var runtime=new RealDeviceRuntime(m);
        await m.SelectBackendAsync(true);await runtime.StartAsync();Assert.Empty(f.Sessions);Assert.True(m.RealBackendSelected);
    }
    [Fact] public async Task KnownDeviceStartupQueriesOnlyTelemetryAndPreservesDraft()
    {
        var f=new FakeGattFactory{Configure=s=>s.CapabilityResponse=[0xAA,0xBB,0x9F,0,0xCC,0xDD]};await using var real=Device(f);real.Selected=new("known","AhaKey",null);
        using var m=Manager(real);using var runtime=new RealDeviceRuntime(m);await m.SelectBackendAsync(true);
        m.Edit(m.Tracker.Draft with{GlobalBrightness=31});await runtime.StartAsync();
        Assert.True(real.Diagnostics.IsLive);Assert.Equal(new byte[]{0,0x9F},f.Sessions.Single().Commands);Assert.Equal(31,m.Tracker.Draft.GlobalBrightness);Assert.Null(m.Tracker.LastDeviceRead);Assert.NotEqual(SyncState.Synced,m.Tracker.State);
        Assert.Equal(CompatibilityState.LegacyTelemetryOnly,CompatibilityPresentation.State(real.Diagnostics));Assert.False(CompatibilityPresentation.CanWritePhysicalConfiguration);
        await m.WriteAsync();Assert.Equal(2,f.Sessions.Single().Commands.Count);Assert.Null(m.Tracker.LastWritten);
    }
    [Theory][InlineData("BleAcquireFailure")][InlineData("BleAdapterUnavailable")][InlineData("BleGattFailure")]
    public async Task FailedKnownDeviceIsBoundedAndNeverUsesMock(string failure)
    {
        var f=new FakeGattFactory{Configure=s=>s.Acquiring=_=>throw new BleException(failure,"Unavailable")};await using var real=Device(f);real.Selected=new("missing","AhaKey",null);
        using var m=Manager(real);using var runtime=new RealDeviceRuntime(m);await m.SelectBackendAsync(true);await runtime.StartAsync();
        Assert.Equal(2,f.Sessions.Count);Assert.All(f.Sessions,s=>{Assert.True(s.Disposed);Assert.Empty(s.Commands);});Assert.True(m.RealBackendSelected);Assert.Same(real,m.Device);Assert.False(runtime.Busy);Assert.Equal("missing",real.Selected.Id);
        await Task.Delay(350);Assert.Equal(2,f.Sessions.Count);
    }
    [Fact] public async Task ExplicitDisconnectCancelsStartupAndRetainsIdentity()
    {
        var entered=new TaskCompletionSource();var f=new FakeGattFactory{Configure=s=>s.Acquiring=async ct=>{entered.TrySetResult();await Task.Delay(Timeout.Infinite,ct);}};
        await using var real=Device(f);real.Selected=new("known","AhaKey",null);using var m=Manager(real);using var runtime=new RealDeviceRuntime(m);await m.SelectBackendAsync(true);
        var start=runtime.StartAsync();await entered.Task;await runtime.DisconnectAsync();await start;
        Assert.True(runtime.ExplicitlyDisconnected);Assert.Single(f.Sessions);Assert.True(f.Sessions[0].Disposed);Assert.Equal("known",real.Selected.Id);Assert.False(real.Diagnostics.IsLive);
    }
    [Fact] public async Task LostSessionGetsOneBoundedBurstAndManualReconnectCanRecover()
    {
        var f=new FakeGattFactory();await using var real=Device(f);real.Selected=new("known","AhaKey",null);using var m=Manager(real);using var runtime=new RealDeviceRuntime(m);await m.SelectBackendAsync(true);await runtime.StartAsync();
        f.Configure=s=>s.Acquiring=_=>throw new BleException("BleAcquireFailure","Off");f.Sessions[0].LoseLink();
        await Until(()=>f.Sessions.Count==3 && !runtime.Busy);await Task.Delay(350);Assert.Equal(3,f.Sessions.Count);Assert.False(real.Diagnostics.IsLive);
        f.Configure=null;await runtime.ConnectAsync(true);Assert.True(real.Diagnostics.IsLive);Assert.Equal(4,f.Sessions.Count);
        await runtime.DisconnectAsync();f.Sessions[^1].LoseLink();await Task.Delay(50);Assert.Equal(4,f.Sessions.Count);
    }
    [Fact] public async Task OrdinaryIoFailureDoesNotEscapeToUi()
    {
        var f=new FakeGattFactory{Configure=s=>s.Acquiring=_=>throw new IOException("failure")};await using var real=Device(f);real.Selected=new("known","AhaKey",null);using var m=Manager(real);using var runtime=new RealDeviceRuntime(m);await m.SelectBackendAsync(true);await runtime.StartAsync();Assert.False(runtime.Busy);Assert.NotNull(m.ErrorKey);
    }
    [Fact] public async Task EveryActualQueryAttemptIsJournalledIncludingTimeout()
    {
        var f=new FakeGattFactory{Configure=s=>s.Respond=false};await using var real=Device(f);real.Selected=new("known","AhaKey",null);var events=new List<BleHistory>();real.Transport.OperationalEvent+=events.Add;
        await Assert.ThrowsAsync<BleException>(()=>real.ConnectAsync());Assert.Single(events,e=>e.Event=="TX");Assert.Equal("AABB00CCDD",events.Single(e=>e.Event=="TX").Detail);Assert.Contains(events,e=>e.Event=="Error");
    }
}

using AhaKey.Core;
using AhaKey.Device;
using Microsoft.Extensions.Logging.Abstractions;
namespace AhaKey.Device.Tests;
public class MockDeviceTests
{
    private static MockAhaKeyDevice Mock() => new() { Latency=TimeSpan.Zero };
    private static DeviceManager Manager(MockAhaKeyDevice device) => new(device,new(),NullLogger<DeviceManager>.Instance);
    [Fact] public async Task ConnectReadDisconnectHasDistinctSessionsAndSimulatedIdentity()
    { var d=Mock(); await d.ConnectAsync(); var r=await d.ReadAsync(); Assert.True(r.Identity.IsSimulation); Assert.Equal(SnapshotSource.MockRead,r.Source); Assert.Equal(91,d.Status.Battery); Assert.Equal(4,r.Configuration.Profiles.Count); await d.DisconnectAsync(); Assert.Null(d.Status.Battery); Assert.Null(d.Status.SessionId); await d.ConnectAsync(); Assert.NotEqual(r.SessionId,d.Status.SessionId); }
    [Fact] public async Task TelemetryAndConfirmationAreDeterministic()
    { var d=Mock(); d.SetTelemetry(23,ConfirmationSwitch.Auto); await d.ConnectAsync(); Assert.Equal(23,d.Status.Battery); Assert.Equal(ConfirmationSwitch.Auto,d.Status.Confirmation); }
    [Fact] public async Task MockStoresKeysDisplayAndLightingUsingSharedModels()
    {
        var d=Mock(); await d.ConnectAsync(); var c=(await d.ReadAsync()).Configuration; var p=c.Profiles[HardwareProfileId.Custom];
        p=p with { Keys=p.Keys.SetItem(PhysicalKey.K2,new KeyboardShortcutAction("Ctrl+K")).SetItem(PhysicalKey.K3,new MacroAction(["Ctrl+C","Ctrl+V"])).SetItem(PhysicalKey.K4,new DisabledAction()), Display=p.Display.SetItem(DisplayState.Working,new(12,"simulated.gif",1200,OptimizationState.Optimized)), Lighting=new(p.Lighting.Mapping.SetItem(IdeEventState.TaskCompleted,3)) };
        c=c with { Profiles=c.Profiles.SetItem(HardwareProfileId.Custom,p), GlobalBrightness=44 }; await d.WriteAsync(c);
        Assert.True(c.EquivalentTo((await d.ReadAsync()).Configuration)); Assert.Equal(new VoiceInputAction(),(await d.ReadAsync()).Configuration.Profiles[HardwareProfileId.Custom].Keys[PhysicalKey.K1]);
    }
    [Fact] public async Task UnsupportedK1WriteIsRejected()
    { var d=Mock(); await d.ConnectAsync(); var c=DeviceConfiguration.Default; var p=c.Profiles[HardwareProfileId.Claude]; c=c with { Profiles=c.Profiles.SetItem(HardwareProfileId.Claude,p with { Keys=p.Keys.SetItem(PhysicalKey.K1,new DisabledAction()) }) }; await Assert.ThrowsAsync<ArgumentException>(()=>d.WriteAsync(c)); }
    [Fact] public async Task ConnectionFailureIsOneShotAndRetryWorks()
    { var d=Mock(); d.NextFailure=MockFailure.ConnectionFailure; await Assert.ThrowsAsync<DeviceOperationException>(()=>d.ConnectAsync()); Assert.Null(d.Status.SessionId); await d.ConnectAsync(); Assert.Equal(ConnectionState.Connected,d.Status.Connection); }
    [Theory] [InlineData(MockFailure.Timeout)] [InlineData(MockFailure.WriteFailure)] [InlineData(MockFailure.InvalidResponse)] [InlineData(MockFailure.DeviceBusy)] [InlineData(MockFailure.DisconnectDuringWrite)]
    public async Task AllWriteFailureScenariosAreDeterministic(MockFailure scenario)
    { var d=Mock(); await d.ConnectAsync(); d.NextFailure=scenario; var error=await Assert.ThrowsAsync<DeviceOperationException>(()=>d.WriteAsync(DeviceConfiguration.Default with { GlobalBrightness=33 })); Assert.Equal(scenario,error.Failure); Assert.Equal(MockFailure.None,d.NextFailure); if(scenario==MockFailure.DisconnectDuringWrite) await d.ConnectAsync(); Assert.Equal(75,(await d.ReadAsync()).Configuration.GlobalBrightness); }
    [Theory] [InlineData(MockFailure.Timeout,SyncState.Indeterminate)] [InlineData(MockFailure.InvalidResponse,SyncState.Indeterminate)] [InlineData(MockFailure.DisconnectDuringWrite,SyncState.Indeterminate)] [InlineData(MockFailure.WriteFailure,SyncState.WriteFailed)] [InlineData(MockFailure.DeviceBusy,SyncState.WriteFailed)]
    public async Task ManagerFailurePreservesDraftAndDoesNotAccept(MockFailure failure,SyncState expected)
    { var d=Mock(); using var m=Manager(d); await m.ConnectAsync(); m.Edit(m.Tracker.Draft with { GlobalBrightness=42 }); d.NextFailure=failure; await m.WriteAsync(); Assert.Equal(expected,m.Tracker.State); Assert.Null(m.Tracker.LastWritten); Assert.Equal(42,m.Tracker.Draft.GlobalBrightness); await m.DisconnectAsync(); await m.ConnectAsync(); Assert.Equal(42,m.Tracker.Draft.GlobalBrightness); Assert.Equal(75,m.Tracker.LastDeviceRead!.Configuration.GlobalBrightness); }
    [Fact] public async Task RealBackendCannotSilentlyFallBackToMock()
    { var d=Mock(); using var m=Manager(d); await m.ConnectAsync(); await m.SelectBackendAsync(true); await m.ConnectAsync(); Assert.True(m.RealBackendSelected); Assert.Equal(ConnectionState.Disconnected,m.State); Assert.Null(d.Status.SessionId); Assert.Equal("UnavailablePhase1",m.ErrorKey); }
    [Fact] public async Task ManagerTransitionsThroughReadWriteAndInvalidatesDisconnect()
    { using var m=Manager(Mock()); var seen=new List<ConnectionState>(); m.Changed+=()=>seen.Add(m.State); await m.ConnectAsync(); await m.WriteAsync(); Assert.Contains(ConnectionState.Connecting,seen); Assert.Contains(ConnectionState.ReadingConfiguration,seen); Assert.Contains(ConnectionState.WritingConfiguration,seen); Assert.Equal(SyncState.WriteAccepted,m.Tracker.State); await m.DisconnectAsync(); Assert.Equal(SyncState.Indeterminate,m.Tracker.State); }
    [Fact] public async Task ConcurrentWriteCannotAcceptAnEditedDraft()
    { var d=new MockAhaKeyDevice { Latency=TimeSpan.FromMilliseconds(20) }; using var m=Manager(d); await m.ConnectAsync(); m.Edit(m.Tracker.Draft with { GlobalBrightness=33 }); var write=m.WriteAsync(); m.Edit(m.Tracker.Draft with { GlobalBrightness=55 }); await m.WriteAsync(); Assert.Equal("ErrorDeviceBusy",m.ErrorKey); await write; Assert.Equal(33,m.Tracker.LastWritten!.Configuration.GlobalBrightness); Assert.Equal(55,m.Tracker.Draft.GlobalBrightness); Assert.Equal(SyncState.UnsavedChanges,m.Tracker.State); }
    [Fact] public async Task CancellationDuringWriteIsIndeterminate()
    { var d=new MockAhaKeyDevice { Latency=TimeSpan.FromMilliseconds(20) }; using var m=Manager(d); await m.ConnectAsync(); using var ct=new CancellationTokenSource(); var operation=m.WriteAsync(ct.Token); ct.Cancel(); await operation; Assert.Equal(SyncState.Indeterminate,m.Tracker.State); Assert.Null(m.Tracker.LastWritten); }
    [Fact] public async Task ShutdownDuringWriteCancelsWithoutDisposingTheInFlightGate()
    {
        var d=new MockAhaKeyDevice { Latency=TimeSpan.FromMilliseconds(20) };
        var m=Manager(d); await m.ConnectAsync(); var write=m.WriteAsync(); m.Dispose();
        await write; Assert.Equal(SyncState.Indeterminate,m.Tracker.State); Assert.Null(m.Tracker.LastWritten);
    }
    [Fact] public void IllegalStateTransitionsAreRejected()
    { var state=new DeviceStateMachine(); Assert.Throws<InvalidOperationException>(()=>state.MoveTo(ConnectionState.WritingConfiguration)); state.MoveTo(ConnectionState.Connecting); state.MoveTo(ConnectionState.Connected); state.MoveTo(ConnectionState.WritingConfiguration); state.MoveTo(ConnectionState.Busy); state.MoveTo(ConnectionState.Connected); }
}

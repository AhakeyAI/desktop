using AhaKey.Core;
using AhaKey.Device;
using Microsoft.Extensions.Logging.Abstractions;
namespace AhaKey.Device.Tests;
public class KeymapTests
{
    private static (MockAhaKeyDevice Mock,DeviceManager Manager,KeymapSession Editor) Create(int latency=1)
    {var mock=new MockAhaKeyDevice{Latency=TimeSpan.FromMilliseconds(latency)};var manager=new DeviceManager(mock,new(),NullLogger<DeviceManager>.Instance);return(mock,manager,new(manager));}
    private static ShortcutGesture Gesture(string text) {Assert.True(ShortcutGesture.TryParse(text,out var g));return g!;}
    [Fact] public async Task ProfilesKeepIndependentDraftsAndDirtyIndicators()
    {
        var (_,m,e)=Create();using(m) {await m.ConnectAsync();e.Profile=HardwareProfileId.Codex;e.SetShortcut(Gesture("Ctrl+Enter"));e.SetDeviceLabel("Accept");Assert.True(e.IsDirty(HardwareProfileId.Codex));Assert.False(e.IsDirty(HardwareProfileId.Claude));e.Profile=HardwareProfileId.Claude;Assert.IsType<DisabledAction>(e.Action);e.SetShortcut(Gesture("Shift+A"));e.Profile=HardwareProfileId.Codex;Assert.Equal(new KeyboardShortcutAction("Ctrl+Enter"),e.Action);Assert.Equal("Accept",e.DeviceLabel);Assert.Null(m.Tracker.LastWritten);}
    }
    [Theory] [InlineData(PhysicalKey.K2)] [InlineData(PhysicalKey.K3)] [InlineData(PhysicalKey.K4)]
    public void SupportedKeysEditAndResetIndependently(PhysicalKey key)
    {var (_,m,e)=Create();using(m){e.SelectKey(key);e.SetShortcut(Gesture("RightCtrl+P"));Assert.Equal(new KeyboardShortcutAction("RightCtrl+P"),e.Action);e.ResetKey();Assert.IsType<DisabledAction>(e.Action);}}
    [Fact] public void K1RejectsEveryGenericEdit()
    {var (_,m,e)=Create();using(m){e.SelectKey(PhysicalKey.K1);Assert.IsType<VoiceInputAction>(e.Action);Assert.Throws<InvalidOperationException>(()=>e.SetShortcut(Gesture("Ctrl+A")));Assert.Throws<InvalidOperationException>(()=>e.SetDeviceLabel("Voice"));Assert.Throws<InvalidOperationException>(e.ClearForSimulation);Assert.Throws<InvalidOperationException>(e.ResetKey);Assert.Throws<ArgumentOutOfRangeException>(()=>e.SelectKey((PhysicalKey)9));}}
    [Fact] public void InvalidLabelsAreRetainedAcrossProfilesButNeverReachTransportDraft()
    {var (_,m,e)=Create();using(m){e.SetDeviceLabel("Принять");Assert.True(e.HasInvalidLabels);Assert.True(e.IsDirty(HardwareProfileId.Codex));Assert.Equal("",e.Configuration.Label(e.Key));e.Profile=HardwareProfileId.Claude;Assert.True(e.IsLabelValid);e.Profile=HardwareProfileId.Codex;Assert.Equal("Принять",e.DeviceLabel);e.SetDeviceLabel("Accept");Assert.False(e.HasInvalidLabels);Assert.Equal("Accept",e.Configuration.Label(e.Key));}}
    [Fact] public async Task SafeTestOnlyDescribesActionWithoutWritingOrSyncing()
    {var (mock,m,e)=Create();using(m){await m.ConnectAsync();e.SetShortcut(Gesture("Ctrl+P"));var before=m.Tracker.Draft;var status=m.Tracker.State;var result=((IActionSimulator)mock).TestAction(e.Key,e.Action);Assert.Equal(e.Action,result.Action);Assert.Same(before,m.Tracker.Draft);Assert.Equal(status,m.Tracker.State);Assert.Null(m.Tracker.LastWritten);Assert.IsType<DisabledAction>((await mock.ReadAsync()).Configuration.Profiles[e.Profile].Keys[e.Key]);}}
    [Fact] public async Task WriteAndReadVerifiesSimulatorAndRetainsAcceptedEvidence()
    {var (_,m,e)=Create();using(m){await m.ConnectAsync();e.SetShortcut(Gesture("Ctrl+Enter"));await m.WriteAndReadAsync();Assert.Equal(SyncState.Synced,m.Tracker.State);Assert.False(e.IsDirty(e.Profile));Assert.NotNull(m.Tracker.LastWritten);Assert.Equal(SnapshotSource.MockRead,m.Tracker.LastDeviceRead!.Source);}}
    [Theory] [InlineData(MockFailure.WriteFailure,SyncState.WriteFailed)] [InlineData(MockFailure.Timeout,SyncState.Indeterminate)] [InlineData(MockFailure.DisconnectDuringWrite,SyncState.Indeterminate)]
    public async Task FailedWritesRetainKeyEdits(MockFailure failure,SyncState state)
    {var (mock,m,e)=Create();using(m){await m.ConnectAsync();e.SetShortcut(Gesture("Ctrl+Enter"));mock.NextFailure=failure;await m.WriteAndReadAsync();Assert.Equal(state,m.Tracker.State);Assert.Equal(new KeyboardShortcutAction("Ctrl+Enter"),e.Action);Assert.True(e.IsDirty(e.Profile));Assert.Null(m.Tracker.LastWritten);}}
    [Fact] public async Task KeyEditsDuringOlderWriteAndProfileSwitchSurviveVerification()
    {var (_,m,e)=Create(30);using(m){await m.ConnectAsync();e.SetShortcut(Gesture("Ctrl+Enter"));var write=m.WriteAndReadAsync();Assert.Equal(SyncState.Writing,m.Tracker.State);e.SetShortcut(Gesture("Ctrl+Shift+P"));e.Profile=HardwareProfileId.Claude;e.SetShortcut(Gesture("Alt+A"));await write;Assert.Equal(SyncState.UnsavedChanges,m.Tracker.State);Assert.True(e.IsDirty(HardwareProfileId.Codex));Assert.True(e.IsDirty(HardwareProfileId.Claude));e.Profile=HardwareProfileId.Codex;Assert.Equal(new KeyboardShortcutAction("Ctrl+Shift+P"),e.Action);Assert.Equal(new KeyboardShortcutAction("Ctrl+Enter"),m.Tracker.LastDeviceRead!.Configuration.Profiles[e.Profile].Keys[e.Key]);}}
    [Fact] public async Task ReadbackFailureCannotClaimSynced()
    {var (mock,m,e)=Create();using(m){await m.ConnectAsync();e.SetShortcut(Gesture("Ctrl+A"));m.Changed+=()=>{if(m.Tracker.State==SyncState.WriteAccepted) mock.NextFailure=MockFailure.InvalidResponse;};await m.WriteAndReadAsync();Assert.Equal(SyncState.Indeterminate,m.Tracker.State);Assert.NotNull(m.Tracker.LastWritten);Assert.Equal(new KeyboardShortcutAction("Ctrl+A"),e.Action);}}
}

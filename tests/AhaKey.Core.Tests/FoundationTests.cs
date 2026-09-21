using System.Collections.Immutable;
using AhaKey.Core;
namespace AhaKey.Core.Tests;
public class FoundationTests
{
    private static ConfigurationSnapshot Read(DeviceConfiguration c) => new(c, SnapshotSource.MockRead, Guid.NewGuid(), new("mock","simulation",true), DateTimeOffset.UnixEpoch);
    [Fact] public void ProfileIdsRemainZeroThroughThree() => Assert.Equal(new[] { 0,1,2,3 }, Profile.Defaults.Select(p => (int)p.HardwareProfileId));
    [Fact] public void RenamePreservesCustomIdentityAndDoesNotBindAnIntegration()
    { var p = Profile.Defaults[3].Rename("VS Code"); Assert.Equal(HardwareProfileId.Custom,p.HardwareProfileId); Assert.Null(p.IntegrationId); Assert.Equal("VS Code",p.DisplayName); }
    [Theory] [InlineData("")] [InlineData("   ")] public void RejectsEmptyName(string name) => Assert.Throws<ArgumentException>(() => Profile.Defaults[3].Rename(name));
    [Fact] public void CannotRenameBuiltInProfile() => Assert.Throws<InvalidOperationException>(() => Profile.Defaults[0].Rename("Other"));
    [Fact] public void LocalDefaultsAreNotDeviceEvidence() { var t = new ConfigurationChangeTracker(); Assert.Equal(SyncState.Indeterminate,t.State); Assert.Null(t.LastDeviceRead); Assert.Null(t.LastWritten); }
    [Fact] public void DraftChangesDoNotMutateReadSnapshot()
    { var t = new ConfigurationChangeTracker(); t.Read(Read(DeviceConfiguration.Default)); t.Edit(t.Draft with { GlobalBrightness = 50 }); Assert.Equal(75,t.LastDeviceRead!.Configuration.GlobalBrightness); Assert.Equal(SyncState.UnsavedChanges,t.State); }
    [Fact] public void RevertingDraftClearsDirtyState()
    { var t = new ConfigurationChangeTracker(); t.Read(Read(DeviceConfiguration.Default)); t.Edit(t.Draft with { GlobalBrightness = 50 }); t.Edit(DeviceConfiguration.Default); Assert.False(t.IsDirty); Assert.Equal(SyncState.Synced,t.State); }
    [Fact] public void EditsDuringWriteSurviveAcceptedOlderSnapshot()
    { var t = new ConfigurationChangeTracker(); var read = Read(DeviceConfiguration.Default); t.Read(read); t.Edit(t.Draft with { GlobalBrightness = 50 }); t.BeginWrite(read.SessionId,read.Identity,DateTimeOffset.UnixEpoch); t.Edit(t.Draft with { GlobalBrightness = 60 }); Assert.Equal(SyncState.Writing,t.State); t.AcceptWrite(read.SessionId); Assert.Equal(50,t.LastWritten!.Configuration.GlobalBrightness); Assert.Equal(60,t.Draft.GlobalBrightness); Assert.Equal(SyncState.UnsavedChanges,t.State); }
    [Fact] public void AcceptanceIsNotReadback()
    { var t = new ConfigurationChangeTracker(); var r = Read(DeviceConfiguration.Default); t.Read(r); t.Edit(t.Draft with { GlobalBrightness = 50 }); t.BeginWrite(r.SessionId,r.Identity,DateTimeOffset.UnixEpoch); t.AcceptWrite(r.SessionId); Assert.Equal(SyncState.WriteAccepted,t.State); Assert.Equal(75,t.LastDeviceRead!.Configuration.GlobalBrightness); t.Read(Read(t.Draft)); Assert.Equal(SyncState.Synced,t.State); }
    [Fact] public void FreshReadSupersedesOlderAcceptedWriteForDirtyComparison()
    { var t = new ConfigurationChangeTracker(); var r = Read(DeviceConfiguration.Default); t.Read(r); t.BeginWrite(r.SessionId,r.Identity,DateTimeOffset.UnixEpoch); t.AcceptWrite(r.SessionId); t.Read(Read(t.Draft with { GlobalBrightness = 42 })); Assert.False(t.IsDirty); Assert.Equal(42,t.Draft.GlobalBrightness); t.Edit(t.Draft); Assert.Equal(SyncState.Synced,t.State); }
    [Fact] public void FirstReadPreservesAnEditedLocalDraft()
    { var t = new ConfigurationChangeTracker(); t.Edit(t.Draft with { GlobalBrightness = 42 }); t.Read(Read(DeviceConfiguration.Default)); Assert.Equal(42,t.Draft.GlobalBrightness); Assert.True(t.IsDirty); }
    [Fact] public void SessionMismatchCannotAcceptWrite()
    { var t = new ConfigurationChangeTracker(); var r = Read(DeviceConfiguration.Default); t.Read(r); t.BeginWrite(r.SessionId,r.Identity,DateTimeOffset.UnixEpoch); Assert.Throws<InvalidOperationException>(() => t.AcceptWrite(Guid.NewGuid())); Assert.Null(t.LastWritten); }
    [Theory] [InlineData(true,SyncState.Indeterminate)] [InlineData(false,SyncState.WriteFailed)] public void FailureDoesNotAcceptDraft(bool uncertain, SyncState expected)
    { var t = new ConfigurationChangeTracker(); var r = Read(DeviceConfiguration.Default); t.Read(r); t.BeginWrite(r.SessionId,r.Identity,DateTimeOffset.UnixEpoch); t.FailWrite(uncertain); Assert.Equal(expected,t.State); Assert.Null(t.LastWritten); }
    [Fact] public void K1CapabilityRejectsArbitraryRemapping()
    { var c = new DeviceCapabilities(true); Assert.False(c.ArbitraryK1Remapping); Assert.True(c.Supports(PhysicalKey.K1,new VoiceInputAction())); Assert.False(c.Supports(PhysicalKey.K1,new KeyboardShortcutAction("Ctrl+C"))); Assert.False(c.Supports(PhysicalKey.K1,new VoiceInputAction("Other"))); Assert.False(c.Supports(PhysicalKey.K2,new IntegrationAction("codex","approve"))); }
    [Fact] public void FourDisplayStatesHaveConfirmedDimensionsAndLimits()
    { Assert.Equal(2,DisplayLimits.Width/DisplayLimits.Height); Assert.Equal(new[] {8,12,12,12},Enum.GetValues<DisplayState>().Select(DisplayLimits.MaximumFrames)); }
    [Fact] public void ValidationRejectsBadDisplayAndMissingProfiles()
    { var c = DeviceConfiguration.Default; var p=c.Profiles[HardwareProfileId.Claude]; var bad=p with { Display=p.Display.SetItem(DisplayState.Default,new(9)) }; var caps = new DeviceCapabilities(true); Assert.Throws<ArgumentException>(()=>caps.Validate(c with { Profiles=c.Profiles.SetItem(HardwareProfileId.Claude,bad) })); Assert.Throws<ArgumentException>(()=>caps.Validate(c with { Profiles=c.Profiles.Remove(HardwareProfileId.Custom) })); }
    [Theory] [InlineData(0)] [InlineData(101)] public void GlobalBrightnessUsesConfirmedRange(int brightness) => Assert.Throws<ArgumentException>(() => new DeviceCapabilities(true).Validate(DeviceConfiguration.Default with { GlobalBrightness=brightness }));
    [Fact] public void LightingEventIdsMatchWindowsOracle()
    { Assert.Equal(4,(int)IdeEventState.SessionStart); Assert.Equal(7,(int)IdeEventState.UserPromptSubmit); Assert.Equal(3,(int)IdeEventState.PreToolUse); Assert.Equal(1,(int)IdeEventState.PermissionRequest); Assert.Equal(2,(int)IdeEventState.PostToolUse); Assert.Equal(0,(int)IdeEventState.Notification); Assert.Equal(6,(int)IdeEventState.TaskCompleted); Assert.Equal(5,(int)IdeEventState.Stop); Assert.Equal(8,(int)IdeEventState.SessionEnd); }
    [Fact] public void StructuralMacroEqualityDoesNotDependOnArrayIdentity()
    { var a=DeviceConfiguration.Default; var p=a.Profiles[HardwareProfileId.Codex]; var b=a with { Profiles=a.Profiles.SetItem(HardwareProfileId.Codex,p with { Keys=p.Keys.SetItem(PhysicalKey.K2,new MacroAction(["Ctrl+C"])) }) }; var c=a with { Profiles=a.Profiles.SetItem(HardwareProfileId.Codex,p with { Keys=p.Keys.SetItem(PhysicalKey.K2,new MacroAction(["Ctrl+C"])) }) }; Assert.True(b.EquivalentTo(c)); }
}

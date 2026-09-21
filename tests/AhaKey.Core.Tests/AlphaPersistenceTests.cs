using AhaKey.Core;
using AhaKey.Services;
using Microsoft.Extensions.Logging;
namespace AhaKey.Core.Tests;
public sealed class AlphaPersistenceTests : IDisposable
{
    private readonly string root=Path.Combine(Path.GetTempPath(),"AhaKey-alpha-tests",Guid.NewGuid().ToString("N"));
    [Fact] public void FirstRunIsSystemRealAndMockRequiresDeveloperMode()
    {
        var store=new SettingsStore(root);var s=store.Load();Assert.Equal(ThemeChoice.System,s.Theme);Assert.Equal(LanguageChoice.System,s.Language);Assert.Equal(BackendChoice.Real,s.EffectiveBackend);Assert.False(s.DeveloperMode);
        store.Save(s with{Backend=BackendChoice.Mock});Assert.Equal(BackendChoice.Real,store.Load().EffectiveBackend);store.Save(s with{Backend=BackendChoice.Mock,DeveloperMode=true});Assert.Equal(BackendChoice.Mock,store.Load().EffectiveBackend);
    }
    [Fact] public void SelectedDevicePersistsAndForgetDoesNotEraseOtherPreferences()
    {
        var store=new SettingsStore(root);var p=new ProfileSelectionService(store);p.Update(s=>s with{BleDeviceId="private-id",BleDeviceName="AhaKey",SelectedProfile=HardwareProfileId.Codex});
        var loaded=new ProfileSelectionService(store);Assert.Equal("private-id",loaded.Settings.BleDeviceId);
        loaded.Update(s=>s with{BleDeviceId=null,BleDeviceName=null,BleDeviceAddress=null});Assert.Null(store.Load().BleDeviceId);Assert.Equal(HardwareProfileId.Codex,store.Load().SelectedProfile);
    }
    [Fact] public void LocalKeymapRoundTripsWithoutPhysicalEvidence()
    {
        var store=new LocalDraftStore(new(root));var draft=DeviceConfiguration.Default;var p=draft.Profiles[HardwareProfileId.Codex];draft=draft with{Profiles=draft.Profiles.SetItem(HardwareProfileId.Codex,p with{Keys=p.Keys.SetItem(PhysicalKey.K2,new KeyboardShortcutAction("Ctrl+Alt+K"))})};store.Save(draft);
        var loaded=new LocalDraftStore(new(root)).Load();Assert.NotNull(loaded);Assert.True(draft.EquivalentTo(loaded));var tracker=new ConfigurationChangeTracker();tracker.Edit(loaded);Assert.Null(tracker.LastDeviceRead);Assert.NotEqual(SyncState.Synced,tracker.State);
    }
    [Fact] public void CorruptDraftIsPreservedAndNeverOverwritten()
    {var store=new LocalDraftStore(new(root));Directory.CreateDirectory(root);File.WriteAllText(store.FilePath,"corrupt");Assert.Null(store.Load());store.Save(DeviceConfiguration.Default);Assert.Equal("corrupt",File.ReadAllText(store.FilePath));Assert.Equal("DraftLoadError",store.ErrorKey);}
    [Fact] public void LogsArePerUserBoundedAndDoNotIncludeExceptionMessages()
    {
        using var log=new SessionLogProvider(new(root));Assert.Equal(Path.Combine(root,"Logs"),log.DirectoryPath);var logger=log.CreateLogger("test");logger.LogError(new IOException("private-device-id"),"Safe failure");for(int i=0;i<205;i++)logger.LogInformation("Lifecycle {Count}",i);Assert.Equal(200,log.Entries.Count);Assert.DoesNotContain("private-device-id",File.ReadAllText(log.FilePath));
    }
    [Fact] public async Task SecondInstanceActivatesOwnerAndCannotOwnUntilRelease()
    {
        using(var owner=new SingleInstanceOwner(root))
        {Assert.True(owner.IsPrimary);var activated=new TaskCompletionSource();owner.ActivationRequested+=()=>activated.TrySetResult();using var second=new SingleInstanceOwner(root);Assert.False(second.IsPrimary);Assert.True(await second.ActivateAsync());await activated.Task.WaitAsync(TimeSpan.FromSeconds(5));}
        using var next=new SingleInstanceOwner(root);Assert.True(next.IsPrimary);
    }
    [Theory][InlineData("ru-RU","ru")][InlineData("zh-TW","zh-CN")][InlineData("en-US","en")][InlineData("fr-FR","en")]
    public void SystemLanguageRecognizesSupportedFamiliesAndFallsBack(string input,string expected)=>Assert.Equal(expected,LocalizationService.SystemCultureName(input));
    [Fact] public void PublishMetadataIsSelfContainedWindowsAlpha()
    {
        var dir=new DirectoryInfo(AppContext.BaseDirectory);while(dir is not null && !File.Exists(Path.Combine(dir.FullName,"AhaKeyStudio.sln")))dir=dir.Parent;Assert.NotNull(dir);
        var project=System.Xml.Linq.XDocument.Load(Path.Combine(dir.FullName,"src/AhaKey.Studio/AhaKey.Studio.csproj"));
        var profile=System.Xml.Linq.XDocument.Load(Path.Combine(dir.FullName,"src/AhaKey.Studio/Properties/PublishProfiles/WinX64Alpha.pubxml"));
        Assert.Equal("WinExe",project.Descendants("OutputType").Single().Value);Assert.Equal("AhaKey Studio",project.Descendants("AssemblyName").Single().Value);Assert.Contains("alpha",System.Xml.Linq.XDocument.Load(Path.Combine(dir.FullName,"Directory.Build.props")).Descendants("Version").Single().Value);Assert.Equal("win-x64",profile.Descendants("RuntimeIdentifier").Single().Value);Assert.Equal("true",profile.Descendants("SelfContained").Single().Value);
    }
    public void Dispose(){if(Directory.Exists(root))Directory.Delete(root,true);}
}

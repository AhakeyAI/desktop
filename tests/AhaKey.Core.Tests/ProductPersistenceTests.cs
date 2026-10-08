using System.Collections.Immutable;
using AhaKey.Core;
using AhaKey.Services;

namespace AhaKey.Core.Tests;
public sealed class ProductPersistenceTests:IDisposable
{
    private readonly string root=Path.Combine(Path.GetTempPath(),"ahakey-product",Guid.NewGuid().ToString("N"));
    [Fact] public void Phase5SettingsMigrateWithoutEnablingNewOptions()
    {
        Directory.CreateDirectory(root);
        File.WriteAllText(Path.Combine(root,"settings.v1.json"),"""{"SchemaVersion":1,"SelectedProfile":"Codex","KeyLocalNames":{"2:1":"My accept"},"BleDeviceId":"private-fixture"}""");
        var store=new SettingsStore(root);var before=store.Load();
        Assert.False(before.IntegrationAutoStart);Assert.False(before.ActivateHardwareProfile);Assert.Empty(before.PhysicalFeedback);
        store.Save(before with{IntegrationAutoStart=true});var after=new SettingsStore(root).Load();
        Assert.Equal("My accept",after.KeyLocalNames["2:1"]);Assert.Equal("private-fixture",after.BleDeviceId);Assert.Equal(HardwareProfileId.Codex,after.SelectedProfile);
    }
    [Fact] public void ProductPreferencesSurviveRestartTogether()
    {
        var store=new SettingsStore(root);var prefs=new ProfileSelectionService(store);
        prefs.Update(s=>s with{SelectedProfile=HardwareProfileId.Codex,IntegrationAutoStart=true,PhysicalFeedback=s.PhysicalFeedback.Add("2:Codex"),DisplaySources=s.DisplaySources.Add("2:0",new("cached.png","Codex.png","Crop","fixture")),KeyLocalNames=s.KeyLocalNames.Add("2:1","Accept custom")});
        var restarted=new ProfileSelectionService(new SettingsStore(root));
        Assert.True(restarted.Settings.IntegrationAutoStart);Assert.Contains("2:Codex",restarted.Settings.PhysicalFeedback);Assert.Equal("Crop",restarted.Settings.DisplaySources["2:0"].Fit);Assert.Equal("Accept custom",restarted.LocalKeyName(HardwareProfileId.Codex,PhysicalKey.K2));
        restarted.Update(s=>s with{PhysicalFeedback=s.PhysicalFeedback.Remove("2:Codex")});Assert.Empty(new SettingsStore(root).Load().PhysicalFeedback);
    }
    [Fact] public void CorruptedPreferencesArePreserved()
    {
        Directory.CreateDirectory(root);var path=Path.Combine(root,"settings.v1.json");File.WriteAllText(path,"{\"PhysicalFeedback\":null}");
        var store=new SettingsStore(root);store.Load();Assert.True(store.IsReadOnly);Assert.Throws<IOException>(()=>store.Save(new()));Assert.Equal("{\"PhysicalFeedback\":null}",File.ReadAllText(path));
    }
    [Fact] public void ReceiptsRequireSameDeviceFirmwareAndValueAndInvalidateBeforeAnotherWrite()
    {
        var store=new SettingsStore(root);var history=new ProductWriteHistory(store);var receipt=new ProductWriteReceipt("fixture","1.0","Key:2:1",ProductWriteHistory.KeyHash("Ctrl+Enter","Send"),DateTimeOffset.UtcNow);
        history.Record(receipt);var restarted=new ProductWriteHistory(store);
        Assert.NotNull(restarted.Find("fixture","1.0",receipt.Target,receipt.ValueHash));Assert.Null(restarted.Find("other","1.0",receipt.Target,receipt.ValueHash));Assert.Null(restarted.Find("fixture","2.0",receipt.Target,receipt.ValueHash));Assert.Null(restarted.Find("fixture","1.0",receipt.Target,ProductWriteHistory.KeyHash("Escape","Send")));
        Assert.False(restarted.Find("fixture","1.0",receipt.Target,receipt.ValueHash)!.BehaviorVerified);
        Assert.Null(restarted.Find(null,"1.0",receipt.Target,receipt.ValueHash));
        Assert.True(restarted.HasMatchingLocalValue(receipt.Target,receipt.ValueHash));
        Assert.False(restarted.HasMatchingLocalValue(receipt.Target,ProductWriteHistory.KeyHash("Ctrl+Enter","Changed")));
        restarted.Record(receipt with{BehaviorVerified=true});Assert.True(history.Find("fixture","1.0",receipt.Target,receipt.ValueHash)!.BehaviorVerified);
        history.Forget("fixture",receipt.Target);Assert.Null(restarted.Find("fixture","1.0",receipt.Target,receipt.ValueHash));
        Assert.False(restarted.HasMatchingLocalValue(receipt.Target,receipt.ValueHash));
    }
    [Fact] public void SimpleCodexUsesOnlyAcceptedWorkingAndNeutralEffects()
    {
        Assert.Equal(1,CodexFeedbackMapping.Simple[IdeEventState.UserPromptSubmit]);Assert.Equal(1,CodexFeedbackMapping.Simple[IdeEventState.PreToolUse]);
        Assert.Equal(0,CodexFeedbackMapping.Simple[IdeEventState.Stop]);Assert.Equal(0,CodexFeedbackMapping.Simple[IdeEventState.SessionEnd]);
        Assert.All(CodexFeedbackMapping.Simple.Values,v=>Assert.Contains(v,new byte[]{0,1}));
    }
    public void Dispose(){if(Directory.Exists(root))Directory.Delete(root,true);}
}

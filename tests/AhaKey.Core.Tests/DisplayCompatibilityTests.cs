using System.Collections;
using System.Globalization;
using System.Resources;
using System.Text.Json.Nodes;
using AhaKey.Core;
using AhaKey.Services;
namespace AhaKey.Core.Tests;

public sealed class DisplayCompatibilityTests : IDisposable
{
    private readonly string root=Path.Combine(Path.GetTempPath(),"AhaKey-display-tests",Guid.NewGuid().ToString("N"));
    private static string Fixture(string name)=>Path.Combine(AppContext.BaseDirectory,"Fixtures",name);
    [Fact] public void FrozenPhase33DraftAndPhase2SettingsRemainReadable()
    {
        Directory.CreateDirectory(root);var settings=new SettingsStore(root);var draft=new LocalDraftStore(settings);
        File.Copy(Fixture("phase33-local-draft.v1.json"),draft.FilePath);
        File.Copy(Fixture("phase2-settings.v1.json"),settings.FilePath);
        var loaded=draft.Load();Assert.NotNull(loaded);Assert.Equal(32,loaded.GlobalBrightness);Assert.Equal(4,loaded.Profiles.Count);
        Assert.All(loaded.Profiles.Values,p=>Assert.Equal(4,p.Display.Count));
        Assert.Equal(HardwareProfileId.Codex,settings.Load().SelectedProfile);Assert.Equal("Принять ответ 接受",settings.Load().KeyLocalNames["2:1"]);
        draft.Save(loaded);Assert.True(loaded.EquivalentTo(draft.Load()!));
        Assert.Contains("\"Oled\"",File.ReadAllText(draft.FilePath));Assert.DoesNotContain("\"Display\"",File.ReadAllText(draft.FilePath));
    }
    [Fact] public void NonemptyLegacyAssetsRetainEveryProfileAndField()
    {
        var fixture=JsonNode.Parse(File.ReadAllText(Fixture("phase33-local-draft.v1.json")))!;
        var profiles=fixture["Configuration"]!["Profiles"]!.AsObject();int i=0;
        foreach(var p in profiles)
        {
            var a=p.Value!["Oled"]!["Working"]!;a["FrameCount"]=++i;a["SourceFile"]=$"fixture-{i}.gif";a["DurationMs"]=100*i;a["Optimization"]=2;
        }
        Directory.CreateDirectory(root);var store=new LocalDraftStore(new(root));File.WriteAllText(store.FilePath,fixture.ToJsonString());
        var config=store.Load();Assert.NotNull(config);i=0;
        foreach(var id in Enum.GetValues<HardwareProfileId>())
        {var a=config.Profiles[id].Display[DisplayState.Working];Assert.Equal(++i,a.FrameCount);Assert.Equal($"fixture-{i}.gif",a.SourceFile);Assert.Equal(i*100,a.DurationMs);Assert.Equal(OptimizationState.Optimized,a.Optimization);}
        store.Save(config);Assert.True(config.EquivalentTo(store.Load()!));
    }
    [Fact] public void DisplayStatesAndWorkingLimitsRemainUnchanged()
    {
        Assert.Equal(new[]{"Default","Working","WaitingError","Completed"},Enum.GetNames<DisplayState>());
        Assert.Equal(new[]{0,1,2,3},Enum.GetValues<DisplayState>().Select(x=>(int)x));
        Assert.Equal(new[]{8,12,12,12},Enum.GetValues<DisplayState>().Select(DisplayLimits.MaximumFrames));
        Assert.Equal(160,DisplayLimits.Width);Assert.Equal(80,DisplayLimits.Height);
    }
    [Theory][InlineData("en")][InlineData("ru")][InlineData("zh-CN")]
    public void OrdinaryUiResourceValuesNeverCallThePanelOled(string culture)
    {
        var resources=new ResourceManager("AhaKey.Services.Resources.Strings",typeof(LocalizationService).Assembly);
        foreach(DictionaryEntry entry in resources.GetResourceSet(CultureInfo.GetCultureInfo(culture),true,true)!)
            Assert.False(((string)entry.Value!).Contains("OLED",StringComparison.OrdinalIgnoreCase),$"{culture}/{entry.Key}");
    }
    public void Dispose(){if(Directory.Exists(root))Directory.Delete(root,true);}
}

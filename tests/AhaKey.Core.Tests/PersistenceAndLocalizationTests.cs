using System.Globalization;
using System.Resources;
using System.Text.Json;
using AhaKey.Core;
using AhaKey.Services;
namespace AhaKey.Core.Tests;
public sealed class PersistenceAndLocalizationTests : IDisposable
{
    private readonly string root=Path.Combine(Path.GetTempPath(),"AhaKeyStudio2-tests",Guid.NewGuid().ToString("N"));
    [Fact] public void FirstRunRequiresSelection() => Assert.Null(new ProfileSelectionService(new SettingsStore(root)).Settings.SelectedProfile);
    [Theory] [InlineData(HardwareProfileId.Claude)] [InlineData(HardwareProfileId.Cursor)] [InlineData(HardwareProfileId.Codex)] [InlineData(HardwareProfileId.Custom)]
    public void SelectionPersists(HardwareProfileId id)
    { new ProfileSelectionService(new SettingsStore(root)).Select(id); Assert.Equal(id,new ProfileSelectionService(new SettingsStore(root)).Settings.SelectedProfile); }
    [Theory] [InlineData(ThemeChoice.System)] [InlineData(ThemeChoice.Light)] [InlineData(ThemeChoice.Dark)] public void ThemePersists(ThemeChoice value)
    { var store=new SettingsStore(root); store.Save(new(Theme:value)); Assert.Equal(value,new SettingsStore(root).Load().Theme); }
    [Theory] [InlineData(LanguageChoice.System)] [InlineData(LanguageChoice.English)] [InlineData(LanguageChoice.Russian)] [InlineData(LanguageChoice.Chinese)] public void LanguagePersists(LanguageChoice value)
    { var store=new SettingsStore(root); store.Save(new(Language:value)); Assert.Equal(value,new SettingsStore(root).Load().Language); }
    [Fact] public void CustomNameAndBackendPersistWithoutChangingProfileId()
    { var service=new ProfileSelectionService(new SettingsStore(root)); service.Select(HardwareProfileId.Custom); service.RenameCustom("Kimi"); service.Update(s=>s with { Backend=BackendChoice.Real }); var loaded=new SettingsStore(root).Load(); Assert.Equal("Kimi",loaded.CustomProfileName); Assert.Equal(HardwareProfileId.Custom,loaded.SelectedProfile); Assert.Equal(BackendChoice.Real,loaded.Backend); }
    [Theory] [InlineData("invalid JSON")] [InlineData("{\"SchemaVersion\":99}")] [InlineData("{\"Language\":999}")] public void CorruptOrFutureSettingsArePreserved(string content)
    { Directory.CreateDirectory(root); var store=new SettingsStore(root); File.WriteAllText(store.FilePath,content); store.Load(); Assert.True(store.IsReadOnly); Assert.NotNull(store.LoadErrorKey); Assert.Throws<IOException>(()=>store.Save(new())); Assert.Equal(content,File.ReadAllText(store.FilePath)); }
    [Fact] public void StorageRootIsSeparateFromLegacy() => Assert.EndsWith(Path.Combine("AhaKey","Studio2"),new SettingsStore().Root);
    [Fact] public void EveryLanguageHasEveryResourceWithoutFallback()
    {
        var resources=new ResourceManager("AhaKey.Services.Resources.Strings",typeof(LocalizationService).Assembly);
        var english=resources.GetResourceSet(CultureInfo.InvariantCulture,true,false)!;
        foreach(var culture in new[] {"ru","zh-CN"})
        {
            var localized=resources.GetResourceSet(CultureInfo.GetCultureInfo(culture),true,false); Assert.NotNull(localized);
            foreach(System.Collections.DictionaryEntry entry in english) Assert.False(string.IsNullOrWhiteSpace(localized.GetString((string)entry.Key)),$"Missing {culture}/{entry.Key}");
        }
    }
    [Fact] public void RuntimeLanguageSwitchRaisesIndexerNotification()
    { var l=new LocalizationService(); int updates=0; l.PropertyChanged+=(_,e)=> { if(e.PropertyName=="Item[]") updates++; }; l.Apply(LanguageChoice.Russian); Assert.Equal("Настройки",l["Settings"]); l.Apply(LanguageChoice.Chinese); Assert.Equal("设置",l["Settings"]); l.Apply(LanguageChoice.English); Assert.Equal("Settings",l["Settings"]); Assert.Equal(3,updates); }
    [Theory] [InlineData(LanguageChoice.English)] [InlineData(LanguageChoice.Russian)] [InlineData(LanguageChoice.Chinese)]
    public void ProductNameDoesNotExposeInternalGeneration(LanguageChoice language)
    { var l=new LocalizationService(); l.Apply(language); Assert.Equal("AhaKey Studio",l["AppTitle"]); }
    [Fact] public void EveryViewResourceReferenceHasATranslation()
    {
        var directory=new DirectoryInfo(AppContext.BaseDirectory);
        while(directory is not null && !File.Exists(Path.Combine(directory.FullName,"AhaKeyStudio.sln"))) directory=directory.Parent;
        Assert.NotNull(directory);
        var source=Path.Combine(directory.FullName,"src","AhaKey.Studio");
        var keys=Directory.EnumerateFiles(source,"*.xaml",SearchOption.AllDirectories)
            .Where(p=>!p.Contains(Path.DirectorySeparatorChar+"obj"+Path.DirectorySeparatorChar) && !p.Contains(Path.DirectorySeparatorChar+"bin"+Path.DirectorySeparatorChar))
            .SelectMany(p=>System.Text.RegularExpressions.Regex.Matches(File.ReadAllText(p),@"Binding (?:L)?\[([A-Za-z][A-Za-z0-9]*)\]").Select(m=>m.Groups[1].Value)).Distinct();
        foreach(var language in new[] {LanguageChoice.English,LanguageChoice.Russian,LanguageChoice.Chinese})
        { var l=new LocalizationService(); l.Apply(language); foreach(var key in keys) Assert.False(l[key].StartsWith('['),$"Missing {language}/{key}"); }
    }
    public void Dispose() { if(Directory.Exists(root)) Directory.Delete(root,true); }
}

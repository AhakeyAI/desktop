using System.IO;
using AhaKey.Device;
using AhaKey.Services;
using AhaKey.Studio.Services;
using CommunityToolkit.Mvvm.ComponentModel;
namespace AhaKey.Studio.ViewModels;
public partial class SettingsViewModel : ObservableObject
{
    private readonly ProfileSelectionService preferences;
    private readonly ThemeService themes;
    private readonly DeviceManager manager;
    private readonly RealDeviceRuntime runtime;
    public LocalizationService L { get; }
    public IReadOnlyList<ChoiceOption<LanguageChoice>> Languages { get; }
    public IReadOnlyList<ChoiceOption<ThemeChoice>> Themes { get; }
    public IReadOnlyList<ChoiceOption<BackendChoice>> Backends { get; }
    [ObservableProperty] private ChoiceOption<LanguageChoice> language;
    [ObservableProperty] private ChoiceOption<ThemeChoice> theme;
    [ObservableProperty] private ChoiceOption<BackendChoice> backend;
    [ObservableProperty] private string? errorKey;
    [ObservableProperty] private bool developerMode;
    public Task BackendChange { get; private set; } = Task.CompletedTask;
    public SettingsViewModel(ProfileSelectionService preferences, LocalizationService l, ThemeService themes, DeviceManager manager,RealDeviceRuntime runtime)
    {
        this.preferences = preferences; L = l; this.themes = themes; this.manager = manager;this.runtime=runtime;developerMode=preferences.Settings.DeveloperMode;
        Languages = [new(LanguageChoice.System,"System",l), new(LanguageChoice.English,"English",l), new(LanguageChoice.Russian,"Russian",l), new(LanguageChoice.Chinese,"Chinese",l)];
        Themes = Enum.GetValues<ThemeChoice>().Select(v => new ChoiceOption<ThemeChoice>(v,v.ToString(),l)).ToArray();
        Backends = Enum.GetValues<BackendChoice>().Select(v => new ChoiceOption<BackendChoice>(v,v.ToString(),l)).ToArray();
        language = Languages.Single(x => x.Value == preferences.Settings.Language);
        theme = Themes.Single(x => x.Value == preferences.Settings.Theme);
        backend = Backends.Single(x => x.Value == preferences.Settings.EffectiveBackend);
    }
    partial void OnLanguageChanged(ChoiceOption<LanguageChoice> value)
    { if (Save(s => s with { Language = value.Value })) L.Apply(value.Value); }
    partial void OnThemeChanged(ChoiceOption<ThemeChoice> value)
    { if (Save(s => s with { Theme = value.Value })) themes.Apply(value.Value); }
    partial void OnBackendChanged(ChoiceOption<BackendChoice> value)
    { if (Save(s => s with { Backend = value.Value })) BackendChange = SwitchBackendAsync(); }
    partial void OnDeveloperModeChanged(bool value)
    {if(Save(s=>s with{DeveloperMode=value,Backend=value?backend.Value:BackendChoice.Real})){if(!value){backend=Backends.Single(x=>x.Value==BackendChoice.Real);OnPropertyChanged(nameof(Backend));}BackendChange=SwitchBackendAsync();}}
    private async Task SwitchBackendAsync()
    {try{await runtime.DisconnectAsync();await manager.SelectBackendAsync(preferences.Settings.EffectiveBackend==BackendChoice.Real);}catch(Exception){ErrorKey="BleNativeFailure";}}
    private bool Save(Func<StudioSettings, StudioSettings> update)
    {
        try { preferences.Update(update); ErrorKey = null; return true; }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { ErrorKey = "SettingsSaveError"; return false; }
    }
}

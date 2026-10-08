using System.IO;
using AhaKey.Device;
using AhaKey.Services;
using AhaKey.Studio.Services;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
namespace AhaKey.Studio.ViewModels;
public partial class SettingsViewModel : ObservableObject
{
    private readonly ProfileSelectionService preferences;
    private readonly ThemeService themes;
    private readonly DeviceManager manager;
    private readonly PhysicalControlRuntime controls;
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
    public IReadOnlyList<ushort> SleepOptions {get;}=[0,5,10,15,30];
    [ObservableProperty] private ushort sleepMinutes;
    [ObservableProperty] private bool sleepBusy;
    [ObservableProperty] private string sleepStatusKey="SleepReadHint";
    public string SleepStatus=>L[SleepStatusKey];
    partial void OnSleepStatusKeyChanged(string value)=>OnPropertyChanged(nameof(SleepStatus));
    [RelayCommand] private async Task ReadSleepAsync()
    {if(SleepBusy)return;SleepBusy=true;SleepStatusKey="SleepLoading";try{SleepMinutes=await manager.ReadStandbyAsync();SleepStatusKey="SleepConfirmed";}catch(Exception ex)when(ex is not OutOfMemoryException){SleepStatusKey="SleepFailed";}finally{SleepBusy=false;}}
    [RelayCommand] private async Task ApplySleepAsync()
    {
        if(SleepBusy)return;SleepBusy=true;SleepStatusKey="SleepApplying";
        try
        {
            if(manager.RealDevice?.Observation is not {IsLive:true,SessionId:{} session})throw new InvalidOperationException();
            ushort requested=SleepMinutes;
            await manager.ExecuteControlsAsync(ApprovedControlPlan.Standby(session,"User applied sleep setting; 04 saves shared configuration",requested),controls.Record);
            if(manager.RealDevice.Observation.SessionId!=session||await manager.ReadStandbyAsync()!=requested)throw new InvalidOperationException();
            SleepStatusKey="SleepConfirmed";
        }
        catch(Exception ex)when(ex is not OutOfMemoryException){SleepStatusKey="SleepFailed";}
        finally{SleepBusy=false;}
    }
    public bool StartWithWindows
    {
        get => WindowsStartup.Enabled;
        set
        {
            try { WindowsStartup.SetEnabled(value); Save(s => s with { StartWithWindows = value }); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Security.SecurityException) { ErrorKey = "SettingsSaveError"; }
            OnPropertyChanged();
        }
    }
    public bool NotifyDeviceDisconnect { get => preferences.Settings.NotifyDeviceDisconnect; set { Save(s => s with { NotifyDeviceDisconnect = value }); OnPropertyChanged(); } }
    public Task BackendChange { get; private set; } = Task.CompletedTask;
    public SettingsViewModel(ProfileSelectionService preferences, LocalizationService l, ThemeService themes, DeviceManager manager,RealDeviceRuntime runtime,PhysicalControlRuntime controls)
    {
        this.preferences = preferences; L = l; this.themes = themes; this.manager = manager;this.runtime=runtime;this.controls=controls;developerMode=preferences.Settings.DeveloperMode;
        Languages = [new(LanguageChoice.System,"System",l), new(LanguageChoice.English,"English",l), new(LanguageChoice.Russian,"Russian",l), new(LanguageChoice.Chinese,"Chinese",l)];
        Themes = Enum.GetValues<ThemeChoice>().Select(v => new ChoiceOption<ThemeChoice>(v,v.ToString(),l)).ToArray();
        Backends = Enum.GetValues<BackendChoice>().Select(v => new ChoiceOption<BackendChoice>(v,v.ToString(),l)).ToArray();
        language = Languages.Single(x => x.Value == preferences.Settings.Language);
        theme = Themes.Single(x => x.Value == preferences.Settings.Theme);
        backend = Backends.Single(x => x.Value == preferences.Settings.EffectiveBackend);
    }
    partial void OnLanguageChanged(ChoiceOption<LanguageChoice> value)
    { if (Save(s => s with { Language = value.Value })) { L.Apply(value.Value); OnPropertyChanged(nameof(SleepStatus)); } }
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

using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Services;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
namespace AhaKey.Studio.ViewModels;
public enum PageId { Home, Keymap, Display, Lighting, Integrations, Device, Diagnostics, Settings }
public sealed partial class ShellViewModel : ObservableObject
{
    public AppVersionService Version=>AppVersionService.Current;
    public ProjectViewModel Project {get;}
    public FirmwareViewModel Firmware {get;}
    private readonly MockAhaKeyDevice mock;
    private readonly SessionLogProvider logs;
    private readonly SettingsStore store;
    private readonly LocalDraftStore drafts;
    private readonly ProfileSelectionService preferences;
    public Services.ProfileActivationRuntime Activation {get;}
    public bool ActivateHardwareProfile {get=>Activation.Enabled;set{try{Activation.Enable(value);}catch(Exception ex)when(ex is not OutOfMemoryException){NoticeKey="SettingsSaveError";}Refresh();}}
    public string HardwareProfile => L["ProductPhysicalProfile"]+": "+(Manager.RealDevice?.Observation is {IsLive:true,Status:{WorkMode:{} mode}} ? Profiles.Cards.FirstOrDefault(c=>(int)c.Profile.HardwareProfileId==mode)?.Name??L["ProductUnknown"] : L["ProductUnknown"]);
    public string ProfileActivationStatus=>L[Activation.ErrorKey??(Activation.Busy?"ProductSwitching":Activation.Available?"ProductProfileAvailable":"ProductProfileUnavailable")];
    public string SummaryKeys=>Keymap.SummaryState;
    public string SummaryDisplay=>Profiles.Selected is {} p?DisplayPlanner.Summary(p.Profile.HardwareProfileId):L["ProductNotConfigured"];
    public string SummaryIntegration=>Integrations.Rows.FirstOrDefault(r=>r.Id.ToString()==Profiles.Selected?.Profile.HardwareProfileId.ToString()) is {} row ? row.Readiness+" · "+row.Service : L["ProductCheckIntegration"];
    public string SummaryLighting=>L[Profiles.Selected is {} p?Controls.FeedbackStateKey(p.Profile.HardwareProfileId,p.Profile.HardwareProfileId.ToString()):"ProductOff"];
    public bool ShowWrite=>!RealMode || IsKeymap;
    public DeviceManager Manager { get; }
    public LocalizationService L { get; }
    public ProfilesViewModel Profiles { get; }
    public SettingsViewModel Settings { get; }
    public KeymapViewModel Keymap { get; }
    public BleViewModel Ble {get;}
    public IntegrationsViewModel Integrations {get;}
    public ControlsViewModel Controls {get;}
    public DisplayPlannerViewModel DisplayPlanner {get;}
    public IReadOnlyList<ChoiceOption<PageId>> Navigation { get; }
    public IReadOnlyList<ChoiceOption<MockFailure>> Failures { get; }
    public IReadOnlyList<ChoiceOption<ConfirmationSwitch>> Switches { get; }
    [ObservableProperty] private ChoiceOption<PageId>? navigationSelection;
    [ObservableProperty] private PageId page = PageId.Home;
    [ObservableProperty] private ChoiceOption<MockFailure> failure;
    [ObservableProperty] private ChoiceOption<ConfirmationSwitch> confirmation;
    [ObservableProperty] private int simulatedBattery = 91;
    [ObservableProperty] private string? noticeKey;
    public ShellViewModel(DeviceManager manager, MockAhaKeyDevice mock, LocalizationService l, ProfilesViewModel profiles,
        SettingsViewModel settings, SessionLogProvider logs, SettingsStore store, KeymapViewModel keymap, BleViewModel ble,LocalDraftStore drafts,IntegrationsViewModel integrations,ControlsViewModel controls,DisplayPlannerViewModel displayPlanner,ProfileSelectionService preferences,Services.ProfileActivationRuntime activation,ProjectViewModel project)
    {
        this.preferences=preferences;Activation=activation;activation.Changed+=Refresh;preferences.Changed+=Refresh;integrations.Manager.Changed+=Refresh;controls.PropertyChanged+=(_,_)=>Refresh();displayPlanner.PropertyChanged+=(_,_)=>Refresh();displayPlanner.ConnectionRequested+=()=>OpenDevice();
        Controls=controls;DisplayPlanner=displayPlanner;Integrations=integrations;this.drafts=drafts;Ble=ble;Ble.PropertyChanged+=(_,_)=>Refresh();Keymap=keymap; Keymap.PropertyChanged+=(_,_)=>Refresh();
        Firmware=new(manager,l);Project=project;Manager = manager; this.mock = mock; L = l; Profiles = profiles; Settings = settings; this.logs = logs; this.store = store;
        controls.SetupRequested+=()=>OpenProductPage("Integrations");
        keymap.VoiceRequested+=()=>{if(Project.VoiceConfigured)Project.TestVoiceAction();else OpenSettings();};
        keymap.KeyTestActive+=Project.SuspendVoice;
        Ble.ProductDiagnostics=()=>new {Integrations=Integrations.Manager.Statuses.Select(s=>new{s.Id,s.Ready,s.ServiceRunning,s.LastActivity}),Display=new {DisplayPlanner.IsPreparing,Frames=DisplayPlanner.Plan?.FrameCount,Profile=DisplayPlanner.Plan?.Profile,State=DisplayPlanner.Plan?.Asset,StartSlot=DisplayPlanner.Plan?.StartSlot},Polling="No idle polling; status on connect/manual refresh or explicitly enabled hardware approvals"};
        Navigation = Enum.GetValues<PageId>().Where(x => x != PageId.Settings).Select(x => new ChoiceOption<PageId>(x,x.ToString(),l)).ToArray();
        navigationSelection = Navigation[0];
        Failures = Enum.GetValues<MockFailure>().Select(x => new ChoiceOption<MockFailure>(x,x.ToString(),l)).ToArray(); failure = Failures[0];
        Switches = Enum.GetValues<ConfirmationSwitch>().Select(x => new ChoiceOption<ConfirmationSwitch>(x,x.ToString(),l)).ToArray(); confirmation = Switches[0];
        Manager.Changed += Refresh; L.PropertyChanged += (_, _) => Refresh();
        Profiles.PropertyChanged += (_, _) => Refresh(); Settings.PropertyChanged += (_, _) => Refresh();
    }
    public bool IsHome => Page == PageId.Home;
    public bool IsSettings => Page == PageId.Settings;
    public bool IsIntegrations => Page == PageId.Integrations;
    public bool IsFoundation => !IsLighting && !IsDisplay && !IsIntegrations && !IsHome && !IsSettings && !IsKeymap && !IsRealDevicePage && !IsRealDiagnosticsPage;
    public bool IsRealDevicePage=>Manager.RealBackendSelected && IsDevice;
    public bool IsRealDiagnosticsPage=>Manager.RealBackendSelected && IsDiagnostics;
    public string ModeLabel=>Manager.RealBackendSelected?DeviceNameLabel:L["Simulation"];
    public string HeaderState=>Manager.RealBackendSelected?$"{Ble.Stage}{(Ble.Fresh && Manager.Device.Status.Battery is {} b?" · "+b+"%":"")}":SyncLabel;
    public string WriteLabel=>L[Manager.RealBackendSelected?(IsKeymap?"ProductApply":"AlphaWriteUnavailable"):"Write"];
    public bool ShowConnect=>Manager.RealBackendSelected && Ble.ShowPicker;
    public bool RealMode=>Manager.RealBackendSelected;
    public string DeviceNameLabel=>Manager.RealBackendSelected?Ble.DeviceName:Manager.Device.Identity.Name;
    public string WriteHint=>L[Manager.RealBackendSelected?(IsKeymap?"PartialKeyRead":"FeatureSpecificControls"):"MockEvidence"];
    public bool IsKeymap => Page == PageId.Keymap;
    public bool IsDisplay => Page == PageId.Display;
    public bool IsLighting => Page == PageId.Lighting;
    public bool IsDiagnostics => Page == PageId.Diagnostics;
    public bool IsDevice => Page == PageId.Device;
    public string PageTitle => L[Page.ToString()];
    public string PageHint => IsFoundation ? L[Page + "Hint"] : "";
    public string BackendLabel => L[Manager.RealBackendSelected ? "Real" : "Mock"];
    public string DeviceStatusLabel => Manager.RealBackendSelected ? Ble.Stage : $"{L[Manager.State.ToString()]} / {L["Simulation"]}";
    public string ConnectionLabel => Manager.RealBackendSelected ? Ble.Stage : L[Manager.State.ToString()];
    public string BatteryLabel => Manager.Device.Status.Battery is { } battery ? $"{battery}%" : L["BatteryUnknown"];
    public string SyncLabel => Manager.RealBackendSelected ? L["BleLocalDraft"] : L[Keymap.HasInvalidLabels && Manager.Tracker.State != SyncState.Writing ? "UnsavedChanges" : Manager.Tracker.State.ToString()];
    public bool IsBusy => Ble.IsWorking || Manager.State is ConnectionState.Connecting or ConnectionState.ReadingConfiguration or ConnectionState.WritingConfiguration;
    public bool CanConfigure => !IsBusy;
    public bool CanUseMock => !Manager.RealBackendSelected && !IsBusy;
    public bool CanConnect => CanUseMock && Manager.State is ConnectionState.Disconnected or ConnectionState.Error;
    public bool CanDisconnect => CanUseMock && Manager.State != ConnectionState.Disconnected;
    public bool CanWrite => Manager.RealBackendSelected?IsKeymap && Keymap.CanWritePhysical:CanUseMock && Manager.State == ConnectionState.Connected && !Keymap.HasInvalidLabels;
    public double Brightness { get => Manager.Tracker.Draft.GlobalBrightness; set { if ((int)value != Manager.Tracker.Draft.GlobalBrightness) Manager.Edit(Manager.Tracker.Draft with { GlobalBrightness = (int)value }); } }
    public string? ErrorText => Activation.ErrorKey is {} activationError
        ? $"{L[activationError]}\n{L["ProductEditing"]}: {Profiles.Selected?.Name ?? L["ProductUnknown"]} · {HardwareProfile}. {L["ProductProfileRecovery"]}"
        : (Project.ErrorKey ?? Settings.ErrorKey ?? Profiles.ErrorKey ?? (RealMode?null:Manager.ErrorKey) ?? store.LoadErrorKey ?? drafts.ErrorKey) is { } key ? L[key] : null;
    public bool HasError => ErrorText is not null;
    public string? NoticeText => NoticeKey is null ? null : L[NoticeKey];
    public string ReadEvidence => Evidence(Manager.Tracker.LastDeviceRead);
    public string WriteEvidence => Evidence(Manager.Tracker.LastWritten);
    public string LogText => Version.SupportText+Environment.NewLine+string.Join(Environment.NewLine, logs.Entries);
    public IReadOnlyList<DisplayStateViewModel> DisplayStates => Enum.GetValues<DisplayState>().Select(x => new DisplayStateViewModel(x, L)).ToArray();
    private string Evidence(ConfigurationSnapshot? snapshot) => snapshot is null ? L["NoEvidence"] : $"{L["MockEvidence"]} · {snapshot.CapturedAt.ToLocalTime():HH:mm:ss}";
    partial void OnNavigationSelectionChanged(ChoiceOption<PageId>? value) { if (value is not null) Page = value.Value; }
    partial void OnPageChanged(PageId value) { Services.CrashEvidence.Operation("Navigate: "+value,Profiles.Selected?.Profile.HardwareProfileId);Keymap.CancelCapture(); Refresh(); if(value==PageId.Integrations && Integrations.Rows.Count==0)_ = Integrations.RefreshCommand.ExecuteAsync(null); }
    partial void OnSimulatedBatteryChanged(int value) { mock.SetTelemetry(value, Confirmation.Value); Refresh(); }
    partial void OnConfirmationChanged(ChoiceOption<ConfirmationSwitch> value) { mock.SetTelemetry(SimulatedBattery, value.Value); Refresh(); }
    partial void OnNoticeKeyChanged(string? value) => OnPropertyChanged(nameof(NoticeText));
    [RelayCommand] private void OpenSettings() { NavigationSelection = null; Page = PageId.Settings; }
    [RelayCommand] private async Task ActivateSelectedAsync(){if(Profiles.Selected is {} selected)await Activation.ActivateAsync(selected.Profile.HardwareProfileId);}
    [RelayCommand] private void OpenProductPage(string name){if(Enum.TryParse<PageId>(name,out var page))NavigationSelection=Navigation.Single(x=>x.Value==page);}
    [RelayCommand] private void OpenDevice() { NavigationSelection=Navigation.Single(x=>x.Value==PageId.Device); }
    [RelayCommand] private async Task ConnectAsync() => await Manager.ConnectAsync();
    [RelayCommand] private async Task DisconnectAsync() => await Manager.DisconnectAsync();
    [RelayCommand] private async Task ReadAsync() => await Manager.ReadAsync();
    [RelayCommand] private async Task WriteAsync()
    {
        if(!CanWrite) return;
        if(Manager.RealBackendSelected){await Keymap.PhysicalWriteCommand.ExecuteAsync(null);return;}
        if(IsKeymap) { await Manager.WriteAndReadAsync(); Keymap.Written(); }
        else await Manager.WriteAsync();
    }
    [RelayCommand] private void ArmFailure() { mock.NextFailure = Failure.Value; NoticeKey = "FailureArmed"; }
    public void Refresh()
    {
        if (System.Windows.Application.Current is null || System.Windows.Application.Current.Dispatcher.HasShutdownStarted) return;
        if (!System.Windows.Application.Current.Dispatcher.CheckAccess()) { System.Windows.Application.Current.Dispatcher.BeginInvoke(Refresh); return; }
        foreach (var name in new[] {nameof(ShowWrite),nameof(ActivateHardwareProfile),nameof(HardwareProfile),nameof(ProfileActivationStatus),nameof(SummaryKeys),nameof(SummaryDisplay),nameof(SummaryIntegration),nameof(SummaryLighting),nameof(ShowConnect),nameof(HeaderState),nameof(WriteLabel),nameof(RealMode), nameof(IsRealDevicePage),nameof(IsRealDiagnosticsPage),nameof(ModeLabel),nameof(DeviceNameLabel),nameof(WriteHint),nameof(IsIntegrations),nameof(IsHome),nameof(IsSettings),nameof(IsFoundation),nameof(IsKeymap),nameof(IsDisplay),nameof(IsLighting),nameof(IsDiagnostics),nameof(IsDevice),nameof(PageTitle),nameof(PageHint),nameof(BackendLabel),nameof(DeviceStatusLabel),nameof(ConnectionLabel),nameof(BatteryLabel),nameof(SyncLabel),nameof(IsBusy),nameof(CanConfigure),nameof(CanUseMock),nameof(CanConnect),nameof(CanDisconnect),nameof(CanWrite),nameof(Brightness),nameof(ErrorText),nameof(HasError),nameof(NoticeText),nameof(ReadEvidence),nameof(WriteEvidence),nameof(LogText),nameof(DisplayStates) }) OnPropertyChanged(name);
    }
}
public sealed class DisplayStateViewModel(DisplayState state, LocalizationService l)
{
    public LocalizationService L => l;
    public string Name => l[state.ToString()];
    public int CurrentFrames => 0;
    public int MaximumFrames => DisplayLimits.MaximumFrames(state);
    public string SourceName => l["NoSource"];
    public string Frames => $"0 / {DisplayLimits.MaximumFrames(state)}";
}

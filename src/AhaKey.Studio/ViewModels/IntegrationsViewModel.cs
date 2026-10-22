using System.Collections.ObjectModel;
using AhaKey.Integrations;
using AhaKey.Services;
using AhaKey.Studio.Services;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace AhaKey.Studio.ViewModels;

public sealed class IntegrationRow(IntegrationStatus status, IntegrationManager manager, LocalizationService l,PhysicalControlRuntime controls,ProfileSelectionService preferences) : ObservableObject
{
    public void Refresh(IntegrationStatus next, IntegrationManager owner)
    {
        status = next; manager = owner; OnPropertyChanged(string.Empty);
    }
    public string Readiness=>l[status.Ready?"ProductReady":status.Configured!=EvidenceState.Yes?"ProductSetupNeeded":status.Trusted==EvidenceState.No?"ProductTrustNeeded":"ProductCheckDetails"];
    public string Feedback=>l["PhysicalFeedback"]+": "+l[preferences.Settings.SelectedProfile is {} p?controls.FeedbackStateKey(p,Id.ToString()):"ProductOff"];
    public IntegrationStatus Status => status;
    public AssistantId Id => status.Id;
    public string Name => Id == AssistantId.Claude ? "Claude Code" : Id.ToString();
    public string Version => status.Version ?? l["IntegrationUnknownVersion"];
    public string Installed => l["IntegrationInstalled"] + ": " + Value(status.Installed);
    public string Configured => l["IntegrationConfigured"] + ": " + Value(status.Configured);
    public string Enabled => l["IntegrationEnabled"] + ": " + Value(status.Enabled);
    public string Trusted => l["IntegrationTrusted"] + ": " + Value(status.Trusted);
    public string Compatible => l["IntegrationCompatible"] + ": " + Value(status.Compatible);
    public string Service => l[manager.Server.Running ? "IntegrationServiceRunning" : "IntegrationServiceStopped"];
    public string Activity => l["IntegrationActivity"] + ": " + l["Activity" + manager.Activity.Get(Id).State];
    public string LastActivity => l["IntegrationLastActivity"] + ": " + (manager.Activity.Get(Id).LastActivity?.ToLocalTime().ToString("HH:mm:ss") ?? l["IntegrationNoActivity"]);
    public string LastEvent => manager.Activity.Get(Id).NativeEvent ?? l["IntegrationNoActivity"];
    public string ConfigPath => status.ConfigPath.Replace(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "%USERPROFILE%", StringComparison.OrdinalIgnoreCase);
    public string Error => status.LastError is {} key ? l[key] : "";
    public bool CanConfigure=>status.Id!=AssistantId.Kimi && status.Installed==EvidenceState.Yes && status.Compatible==EvidenceState.Yes;
    public bool CanRemove=>status.Id!=AssistantId.Kimi && status.Configured==EvidenceState.Yes;
    public string PrimaryAction=>!CanConfigure?"Details":status.Configured!=EvidenceState.Yes?"Install":status.Enabled==EvidenceState.No?"Repair":manager.Server.Running?"StopService":"StartService";
    public bool HasPrimary=>PrimaryAction!="Details";
    public string PrimaryLabel=>l["Integration"+PrimaryAction];
    public bool HasMaintenance=>CanConfigure || CanRemove;
    private string Value(EvidenceState value) => l["Evidence" + value];
}

public sealed partial class IntegrationsViewModel : ObservableObject, IDisposable
{
    public IntegrationManager Manager { get; private set; }
    public LocalizationService L { get; }
    public ObservableCollection<IntegrationRow> Rows { get; } = [];
    [ObservableProperty] private IntegrationRow? selected;
    [ObservableProperty] private bool busy;
    [ObservableProperty] private string? errorKey;
    [ObservableProperty] private ConfigurationPlan? plan;
    [ObservableProperty] private string? receiptText;
    [ObservableProperty] private bool hardwareAuto;
    private readonly System.Windows.Threading.DispatcherTimer timer;
    private readonly ProfileSelectionService preferences;
    private readonly PhysicalControlRuntime controls;
    public bool AutoStart {get=>preferences.Settings.IntegrationAutoStart;set{try{preferences.Update(s=>s with{IntegrationAutoStart=value});}catch(Exception ex)when(ex is not OutOfMemoryException){ErrorKey="SettingsSaveError";}OnPropertyChanged();}}
    public IntegrationsViewModel(IntegrationRuntime runtime, LocalizationService l,ProfileSelectionService preferences,PhysicalControlRuntime controls)
    {
        this.preferences=preferences;this.controls=controls;controls.Changed+=Update;preferences.Changed+=Update;
        Manager = runtime.Manager; L = l; Manager.Changed += Update; L.PropertyChanged += (_, _) => Update();
        timer = new() { Interval = TimeSpan.FromSeconds(5) }; timer.Tick += (_, _) => Update(); timer.Start();
    }
    // Offline capture injects fixtures without touching the actual host or its config.
    public void UseFixture(IntegrationManager fixture) { Manager.Changed -= Update; Manager = fixture; Manager.Changed += Update; Update(); }
    public bool HasSelection => Selected is not null;
    public bool HasPlan => Plan is not null;
    public bool HasError => ErrorKey is not null || Manager.Server.ErrorKey is not null;
    public bool CanEdit => !Busy && Selected is { Id: not AssistantId.Kimi };
    public bool CanConfigure => CanEdit && Selected!.Status.Installed == EvidenceState.Yes && Selected.Status.Compatible == EvidenceState.Yes;
    public string ErrorText => L[ErrorKey ?? Manager.Server.ErrorKey ?? "IntegrationNoError"];
    public string ServiceText => L[Manager.Server.Running ? "IntegrationServiceRunning" : "IntegrationServiceStopped"];
    public bool CanApply => !Busy && Plan is { Files.Count: > 0 };
    public string PlanText => Plan is null ? "" : Plan.Files.Count == 0 ? L["IntegrationNoChanges"] :
        string.Join("\n\n", Plan.HookChanges.Select(c =>
            $"{c.Event} · {L["IntegrationEntryCount"]}: {c.BeforeCount} → {c.AfterCount}\n{Sanitize(c.Command)}\nmatcher: {c.Matcher} · timeout: {c.Timeout}s")) + "\n\n" +
        string.Join("\n\n", Plan.Files.Select(f =>
            $"{Sanitize(f.Path)}\n{L[f.Purpose]}\nSHA-256: {f.BeforeHash} → {f.AfterHash}"));
    public string EventText => Manager.Activity.History.Count == 0 ? L["IntegrationNoActivity"] : string.Join("\n", Manager.Activity.History.Select(e =>
        $"{e.At.ToLocalTime():HH:mm:ss} · {e.Integration} · {e.Event} · {e.NativeEvent}\n{L["EventResult" + e.Result]}{(e.ApprovalSource is null ? "" : " · " + e.ApprovalSource)}"));
    private static string Sanitize(string path) => path.Replace(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "%USERPROFILE%", StringComparison.OrdinalIgnoreCase);
    partial void OnSelectedChanged(IntegrationRow? value) { Plan = null; ErrorKey = null; ReceiptText = null; Notify(); }
    partial void OnPlanChanged(ConfigurationPlan? value) => Notify();
    partial void OnBusyChanged(bool value) => Notify();
    partial void OnErrorKeyChanged(string? value) => Notify();
    partial void OnHardwareAutoChanged(bool value) { Manager.Approvals.HardwareAutoEnabled = value; }
    private void Notify()
    {
        foreach(var name in new[] { nameof(CanApply), nameof(HasSelection), nameof(HasPlan), nameof(HasError), nameof(CanEdit), nameof(CanConfigure), nameof(ErrorText), nameof(ServiceText), nameof(PlanText), nameof(EventText) }) OnPropertyChanged(name);
    }
    public void Update()
    {
        var dispatcher=System.Windows.Application.Current?.Dispatcher;
        if(dispatcher is null || dispatcher.HasShutdownStarted)return;
        if(!dispatcher.CheckAccess()){dispatcher.BeginInvoke(Update);return;}
        foreach (var status in Manager.Statuses)
        {
            var row = Rows.FirstOrDefault(r => r.Id == status.Id);
            if (row is null) Rows.Add(new(status, Manager, L,controls,preferences)); else row.Refresh(status, Manager);
        }
        Notify();
    }
    [RelayCommand] private async Task RefreshAsync()
    {
        if(Busy)return;Busy=true;
        try { await Manager.RefreshAsync(); ErrorKey=null; }
        catch(Exception ex) when(ex is not OutOfMemoryException){ErrorKey="IntegrationInspectFailed";}
        finally{Busy=false;}
    }
    [RelayCommand] private void StartService() { Manager.Server.Start(); Update(); }
    [RelayCommand] private async Task StopServiceAsync() { await Manager.Server.DisposeAsync(); await controls.StopFeedbackAsync(); Update(); }
    [RelayCommand] private async Task PrimaryAsync(AssistantId id)
    {
        if(Busy)return;
        var row=Rows.Single(r=>r.Id==id);
        switch(row.PrimaryAction)
        {
            case "StartService":StartService();break;
            case "StopService":await StopServiceAsync();break;
            case "Install":case "Repair":Selected=row;Prepare(row.PrimaryAction);break;
            default:Selected=row;break;
        }
    }
    public void PrepareFor(IntegrationRow row,string action){if(Busy)return;Selected=row;Prepare(action);}
    public void OpenConfiguration(IntegrationRow row)
    {
        try
        {
            var path=Environment.ExpandEnvironmentVariables(row.ConfigPath);
            var folder=System.IO.Path.GetDirectoryName(path);
            while(folder is not null && !System.IO.Directory.Exists(folder))folder=System.IO.Path.GetDirectoryName(folder);
            if(folder is not null)System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(folder){UseShellExecute=true});
        }
        catch(Exception ex)when(ex is not OutOfMemoryException){ErrorKey="IntegrationInspectFailed";}
    }
    [RelayCommand] private void Details(AssistantId id) { Selected=Rows.Single(r=>r.Id==id); }
    [RelayCommand] private void Back() { Selected=null; }
    [RelayCommand] private void Prepare(string action)
    {
        if(!CanEdit || !Enum.TryParse<ConfigurationAction>(action,out var parsed) || parsed!=ConfigurationAction.Remove && !CanConfigure)return;
        try { Plan=Manager.Preview(Selected!.Id,parsed);ErrorKey=null; }
        catch(Exception ex) when(ex is not OutOfMemoryException){Plan=null;ErrorKey="IntegrationUnsafeConfig";}
    }
    [RelayCommand] private void CancelPlan() { Plan=null; }
    [RelayCommand] private async Task ApplyAsync()
    {
        if(!CanApply || Plan is null)return; var approved=Plan;Busy=true;
        try {var receipt=await Manager.ApplyAsync(approved);ReceiptText=L["IntegrationChangesSaved"]+"\n"+Sanitize(receipt.BackupDirectory);Plan=null;}
        catch(Exception ex) when(ex is not OutOfMemoryException){ErrorKey="IntegrationApplyFailed";Plan=null;}
        finally{Busy=false;}
    }
    public void Dispose(){timer.Stop();Manager.Changed-=Update;}
}

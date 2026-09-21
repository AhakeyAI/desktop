using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Integrations;
using AhaKey.Services;

namespace AhaKey.Studio.Services;

public sealed class IntegrationRuntime : IAsyncDisposable
{
    private readonly ProfileSelectionService preferences;
    private readonly PhysicalControlRuntime controls;
    public AssistantRuntimeCoordinator Coordinator {get;}=new();
    private readonly System.Windows.Threading.DispatcherTimer aggregationTimer=new(){Interval=TimeSpan.FromSeconds(1)};
    private Guid? deviceSession;
    private bool disposed;
    private readonly SemaphoreSlim aggregateGate=new(1,1);
    private DeviceManager device=null!;
    public IntegrationManager Manager { get; }
    public string? StartupError {get;private set;}
    public async Task InitializeAsync()
    {
        try { await IntegrationStartup.InitializeAsync(Manager,preferences.Settings.IntegrationAutoStart); }
        catch(Exception ex)when(ex is not OutOfMemoryException){StartupError="IntegrationInspectFailed";}
    }
    public IntegrationRuntime(DeviceManager device, SettingsStore settings,PhysicalControlRuntime controls,ProfileSelectionService profiles)
    {
        preferences=profiles;this.controls=controls;this.device=device;
        var approvals = new ApprovalService(async ct =>
        {
            // A normal hook must not wake the keyboard merely to discover that hardware approval is off.
            if(Manager?.Approvals.HardwareAutoEnabled!=true)return new ApprovalSnapshot(false,false,SwitchEvidence.Unknown);
            var started = DateTimeOffset.UtcNow;
            var value = await device.RefreshApprovalStatusAsync(ct);
            bool fresh = value is { IsLive: true, StatusAt: {} at } && at >= started && at <= DateTimeOffset.UtcNow;
            return new(value?.IsLive == true, fresh, value?.Status?.Confirmation switch
            {
                ConfirmationSwitch.Auto => SwitchEvidence.Auto,
                ConfirmationSwitch.Manual => SwitchEvidence.Manual,
                _ => SwitchEvidence.Unknown
            });
        });
        Manager = new(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), settings.Root, new HostInspection(), approvals);
        Manager.Server.EventReceived+=ev=>
        {
            var received=DateTimeOffset.UtcNow;
            System.Windows.Application.Current.Dispatcher.BeginInvoke(async ()=>
            {
                if(!Manager.Server.Running || DateTimeOffset.UtcNow-received>TimeSpan.FromSeconds(1))return;
                UpdateGeneration();Coordinator.Accept(ev);await AggregateAsync();
            });
        };
        aggregationTimer.Tick+=async(_,_)=>await AggregateAsync();aggregationTimer.Start();
        Manager.Server.Changed+=()=>{if(!Manager.Server.Running){Coordinator.Clear();_ = StopAfterAggregateAsync();}};
    }
    private async Task StopAfterAggregateAsync()
    {await aggregateGate.WaitAsync();try{await controls.StopFeedbackAsync();}finally{aggregateGate.Release();}}
    private void UpdateGeneration()
    {var current=device.RealDevice?.Observation is {IsLive:true} observation?observation.SessionId:null;if(current!=deviceSession){deviceSession=current;Coordinator.Clear();}}
    private async Task AggregateAsync()
    {
        if(disposed||!await aggregateGate.WaitAsync(0))return;
        try{UpdateGeneration();if(!Manager.Server.Running||preferences.Settings.SelectedProfile is not {} profile)return;
            var aggregate=Coordinator.Aggregate(id=>controls.FeedbackEnabled(profile,id.ToString()));
            await controls.ApplyAggregateAsync(profile,aggregate.Owner?.Integration.ToString(),aggregate.State>=AssistantProductState.Working,()=>!disposed&&Manager.Server.Running&&Coordinator.Generation==aggregate.Generation,aggregate.State);}
        finally{aggregateGate.Release();}
    }
    public async ValueTask DisposeAsync() {disposed=true;aggregationTimer.Stop();Coordinator.Clear();Manager.Approvals.Dispose();await Manager.Server.DisposeAsync();await aggregateGate.WaitAsync();try{await controls.StopFeedbackAsync();}finally{aggregateGate.Release();}}
}

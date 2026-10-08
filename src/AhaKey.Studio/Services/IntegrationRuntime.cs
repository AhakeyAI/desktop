using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Integrations;
using AhaKey.Services;
using AhaKey.Protocol;

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
    private readonly Dictionary<byte,(AssistantId Integration,string Owner,HardwareProfileId Profile,byte State)> ownedSlots=[];
    private Guid? taskSession;private DateTimeOffset lastHeartbeat;
    public bool TasksEnabled {get;private set;}
    public string TasksStatusKey {get;private set;}="TasksOff";
    public event Action? TasksChanged;
    public async Task SetTasksEnabledAsync(bool enabled)
    {
        await aggregateGate.WaitAsync();
        try
        {
            if(!enabled){await ReleaseTasksAsync();return;}
            if(device.RealDevice?.Observation is not {IsLive:true,SessionId:{} session,Capabilities:{SupportedContract:true}})throw new InvalidOperationException();
            // Existing active slots may belong to another host. Refuse to take them over.
            FirmwareTaskStatus? status=null;
            await device.ExecuteControlsAsync(ApprovedControlPlan.TaskStatus(session,"User enabled multiple tasks"),e=>{controls.Record(e);if(e.Rx is {} rx)status=TaskProtocol.ParseStatus(Convert.FromHexString(rx));});
            if(status is null||status.Slots.Any(s=>s.State!=0))throw new InvalidOperationException("Task slots are occupied.");
            await controls.StopFeedbackAsync();
            await device.ExecuteControlsAsync(ApprovedControlPlan.TaskMode(session,"User enabled multiple tasks",true),controls.Record);
            taskSession=session;TasksEnabled=true;lastHeartbeat=DateTimeOffset.UtcNow;TasksStatusKey="TasksOn";TasksChanged?.Invoke();
        }
        catch(Exception ex)when(ex is not OutOfMemoryException){TasksEnabled=false;TasksStatusKey="TasksFailed";TasksChanged?.Invoke();}
        finally{aggregateGate.Release();}
    }
    private async Task ReleaseTasksAsync()
    {
        TasksEnabled=false;
        try
        {
            if(taskSession is {} session && device.RealDevice?.Observation is {IsLive:true} observation && observation.SessionId==session)
            {
                foreach(var slot in ownedSlots.Keys.ToArray())await device.ExecuteControlsAsync(ApprovedControlPlan.TaskSlot(session,"Release Studio task slot",slot,ownedSlots[slot].Profile,0,0),controls.Record);
                await device.ExecuteControlsAsync(ApprovedControlPlan.TaskMode(session,"User disabled multiple tasks",false),controls.Record);
            }
            TasksStatusKey="TasksOff";
        }
        catch(Exception ex)when(ex is not OutOfMemoryException){TasksStatusKey="TasksCleanupPending";}
        finally{ownedSlots.Clear();taskSession=null;TasksChanged?.Invoke();}
    }
    private async Task SyncTasksAsync(HardwareProfileId profile)
    {
        if(!TasksEnabled)return;
        if(device.RealDevice?.Observation is not {IsLive:true} observation||observation.SessionId!=taskSession)
        {TasksEnabled=false;ownedSlots.Clear();taskSession=null;TasksStatusKey="TasksReconnect";TasksChanged?.Invoke();return;}
        if(ownedSlots.Count>0&&DateTimeOffset.UtcNow-lastHeartbeat>TimeSpan.FromSeconds(25))
        {TasksEnabled=false;ownedSlots.Clear();taskSession=null;TasksStatusKey="TasksReconnect";TasksChanged?.Invoke();return;}
        if(device.Operations.Current is not null||device.Operations.ShutdownRequested||controls.UsbOperationBusy)return;
        try
        {
            var eligible=Coordinator.Sessions.Where(t=>controls.FeedbackEnabled(profile,t.Integration.ToString())).OrderByDescending(t=>t.Priority).ThenBy(t=>t.Sequence).ToArray();
            var selected=eligible.Take(4).ToArray();
            var session=taskSession!.Value;
            // Release only slots owned in this session. Assignment stays stable for unchanged tasks.
            foreach(var slot in ownedSlots.Keys.ToArray())
                if(!selected.Any(t=>t.Integration==ownedSlots[slot].Integration&&t.Ownership==ownedSlots[slot].Owner))
                {await device.ExecuteControlsAsync(ApprovedControlPlan.TaskSlot(session,"Expire Studio task",slot,ownedSlots[slot].Profile,0,0),controls.Record);ownedSlots.Remove(slot);}
            foreach(var task in selected)
            {
                byte state=task.State switch{AssistantProductState.Working=>1,AssistantProductState.NeedsAttention=>2,AssistantProductState.Done=>3,AssistantProductState.Error=>4,_=>0};
                byte slot=ownedSlots.FirstOrDefault(x=>x.Value.Integration==task.Integration&&x.Value.Owner==task.Ownership).Key;
                bool existing=ownedSlots.Any(x=>x.Value.Integration==task.Integration&&x.Value.Owner==task.Ownership);
                if(!existing)slot=Enumerable.Range(0,4).Select(x=>(byte)x).First(x=>!ownedSlots.ContainsKey(x));
                if(!existing||ownedSlots[slot].State!=state||ownedSlots[slot].Profile!=profile)
                {await device.ExecuteControlsAsync(ApprovedControlPlan.TaskSlot(session,"Route Studio task",slot,profile,state,1),controls.Record);ownedSlots[slot]=(task.Integration,task.Ownership,profile,state);}
            }
            if(ownedSlots.Count>0&&DateTimeOffset.UtcNow-lastHeartbeat>=TimeSpan.FromSeconds(10))
            {
                byte? mask=null;
                await device.ExecuteControlsAsync(ApprovedControlPlan.TaskHeartbeat(session,"Maintain owned Studio tasks"),e=>{controls.Record(e);if(e.Rx is {} rx)mask=Convert.FromHexString(rx)[4];});
                int expected=ownedSlots.Where(x=>x.Value.State!=0).Sum(x=>1<<x.Key);
                if(mask!=expected)throw new InvalidOperationException("Owned task mask differs from firmware; explicit enable required.");
                lastHeartbeat=DateTimeOffset.UtcNow;
            }
            TasksStatusKey=eligible.Length>4?"TasksOverflow":"TasksOn";TasksChanged?.Invoke();
        }
        catch(Exception ex)when(ex is not OutOfMemoryException)
        {TasksEnabled=false;ownedSlots.Clear();taskSession=null;TasksStatusKey="TasksFailed";TasksChanged?.Invoke();}
    }
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
    {await aggregateGate.WaitAsync();try{await ReleaseTasksAsync();await controls.StopFeedbackAsync();}finally{aggregateGate.Release();}}
    private void UpdateGeneration()
    {var current=device.RealDevice?.Observation is {IsLive:true} observation?observation.SessionId:null;if(current!=deviceSession){deviceSession=current;Coordinator.Clear();}}
    private async Task AggregateAsync()
    {
        if(disposed||!await aggregateGate.WaitAsync(0))return;
        try{UpdateGeneration();if(!Manager.Server.Running||device.RealDevice?.Observation.Status?.WorkMode is not {} mode || mode>3)return;
            var profile=(HardwareProfileId)mode;
            await SyncTasksAsync(profile);
            if(TasksEnabled)return;
            var aggregate=Coordinator.Aggregate(id=>controls.FeedbackEnabled(profile,id.ToString()));
            await controls.ApplyAggregateAsync(profile,aggregate.Owner?.Integration.ToString(),aggregate.State>=AssistantProductState.Working,()=>!disposed&&Manager.Server.Running&&Coordinator.Generation==aggregate.Generation,aggregate.State);}
        finally{aggregateGate.Release();}
    }
    public async ValueTask DisposeAsync() {disposed=true;aggregationTimer.Stop();Coordinator.Clear();Manager.Approvals.Dispose();await Manager.Server.DisposeAsync();await aggregateGate.WaitAsync();try{await ReleaseTasksAsync();await controls.StopFeedbackAsync();}finally{aggregateGate.Release();}}
}

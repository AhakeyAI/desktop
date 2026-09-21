using AhaKey.Core;
using AhaKey.Device.Ble;
using Microsoft.Extensions.Logging;
namespace AhaKey.Device;
public sealed class DeviceManager(IAhaKeyDevice device, ConfigurationChangeTracker tracker, ILogger<DeviceManager> logger, RealAhaKeyDevice? realDevice=null) : IDisposable
{
    public DeviceOperationCoordinator Operations {get;} = new();
    private DeviceOperationCoordinator gate => Operations;
    private readonly DeviceStateMachine state = new();
    private readonly CancellationTokenSource lifetime = new();
    public RealAhaKeyDevice? RealDevice=>realDevice;
    public IAhaKeyDevice Device => RealBackendSelected && realDevice is not null ? realDevice : device;
    public ConfigurationChangeTracker Tracker => tracker;
    public ConnectionState State => RealBackendSelected && state.State==ConnectionState.Connected && realDevice?.Observation.IsLive==false ? ConnectionState.Error : state.State;
    public string? ErrorKey { get; private set; }
    public bool RealBackendSelected { get; private set; }
    public event Action? Changed;
    public void Edit(DeviceConfiguration draft) { device.Capabilities.Validate(draft); tracker.Edit(draft); Changed?.Invoke(); }
    public Task SelectBackendAsync(bool real)
    { realDevice?.CancelCurrent();return Run(async token =>
    {
        await Device.DisconnectAsync(token); state.MoveTo(ConnectionState.Disconnected); tracker.InvalidateSession();
        RealBackendSelected = real; ErrorKey = real && realDevice is null ? "UnavailablePhase1" : null;
    }, false, default, true); }
    public Task ConnectAsync(CancellationToken ct = default) => Run(async token =>
    {
        if (RealBackendSelected && realDevice is null) { ErrorKey = "UnavailablePhase1"; return; }
        if (State == ConnectionState.Connected) return;
        state.MoveTo(ConnectionState.Connecting); Changed?.Invoke();
        await Device.ConnectAsync(token); state.MoveTo(ConnectionState.Connected);
        if(!RealBackendSelected) await ReadCore(token);
    }, false, ct);
    public Task DisconnectAsync(CancellationToken ct = default)
    { realDevice?.CancelCurrent(); return Run(async token =>
    {
        await Device.DisconnectAsync(token); state.MoveTo(ConnectionState.Disconnected); tracker.InvalidateSession();
    }, false, ct, true); }
    public Task ReadAsync(CancellationToken ct = default) => Run(ReadCore, false, ct);
    public async Task<PhysicalObservation?> RefreshApprovalStatusAsync(CancellationToken ct)
    {
        if(ct.IsCancellationRequested)return null;
        // A hook's 500 ms decision deadline is not the lifetime of an already-sent device query.
        // Fail the caller closed, but retain ownership until the bounded transport query drains.
        try{return await RefreshApprovalStatusCoreAsync().WaitAsync(ct);}
        catch(OperationCanceledException){return null;}
    }
    private async Task<PhysicalObservation?> RefreshApprovalStatusCoreAsync()
    {
        if (!RealBackendSelected || realDevice is null || !await gate.WaitAsync(0, lifetime.Token)) return null;
        try { gate.Describe("Approval status",realDevice.Observation.SessionId,realDevice.ActiveTransport,false); return await realDevice.RefreshApprovalStatusAsync(lifetime.Token); }
        catch (Exception ex) when (ex is not OutOfMemoryException) { gate.Fail(false);return null; }
        finally { gate.Release(); Changed?.Invoke(); }
    }
    public async Task<System.Collections.Immutable.ImmutableArray<byte>> ReadConfigAsync(byte resource,byte index,Action<PhysicalCommandEvidence> record,CancellationToken ct=default)
    {
        if(!RealBackendSelected||realDevice is null||!await gate.WaitAsync(0,ct))throw new InvalidOperationException("Real idle device required.");
        using var linked=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime.Token);linked.CancelAfter(TimeSpan.FromSeconds(30));
        try{gate.Describe("9D partial read",realDevice.Observation.SessionId,realDevice.ActiveTransport,false);var result=await realDevice.ReadConfigAsync(resource,index,record,linked.Token);gate.Confirm("Resource received");return result;}
        catch{gate.Fail(false);throw;}
        finally{gate.Release();Changed?.Invoke();}
    }
    public async Task UploadDisplayAsync(ApprovedDisplayUpload approval,Action<DisplayTransferEvidence> record,Action<DisplayResponseEvidence> responseRecord,CancellationToken ct=default)
    {
        if(realDevice is not null)gate.RequireRoute(OperationRequirement.UploadDisplayBulk,realDevice.ActiveTransport);
        if(!RealBackendSelected || realDevice is null || !await gate.WaitAsync(0,ct))throw new InvalidOperationException("Real idle device required.");
        using var linked=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime.Token);
        linked.CancelAfter(TimeSpan.FromMinutes(5));
        try{gate.Describe("Display upload",realDevice.Observation.SessionId,realDevice.ActiveTransport,true);await realDevice.UploadDisplayAsync(approval,record,e=>{responseRecord(e);if(!e.Stage.StartsWith("REJECTED",StringComparison.Ordinal))gate.Confirm(e.Stage,e.Stage is "82 binding" or "93 binding",e.Stage.Contains("save",StringComparison.OrdinalIgnoreCase));},linked.Token);}
        catch{gate.Fail(true);throw;}
        finally{gate.Release();Changed?.Invoke();}
    }
    public async Task ExecuteControlsAsync(ApprovedControlPlan plan,Action<PhysicalCommandEvidence> record,CancellationToken ct=default)
    {
        if(!RealBackendSelected || realDevice is null)throw new InvalidOperationException("Physical controls require the real backend.");
        if(!await gate.WaitAsync(0,ct))throw new InvalidOperationException("Device busy.");
        using var linked=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime.Token);
        linked.CancelAfter(TimeSpan.FromSeconds(30));
        try{gate.Describe("Controls",plan.Session,realDevice.ActiveTransport,plan.Commands.Any(x=>x.Opcode is 0x73 or 0x84 or 0x85 or 4));await realDevice.ExecuteControlsAsync(plan,e=>{record(e);if(e.Error is null && e.ResponseAt is not null)gate.Confirm(e.Operation,save:e.Tx=="AABB04CCDD");},linked.Token);}
        catch{gate.Fail(plan.Commands.Any(x=>x.Opcode is 0x73 or 0x84 or 0x85 or 4));throw;}
        finally{gate.Release();Changed?.Invoke();}
    }
    public async Task<bool> ExecuteFeedbackAsync(ApprovedControlPlan plan,HardwareProfileId profile,Func<bool> enabled,
        Action beforeSend,Action<PhysicalCommandEvidence> record,CancellationToken ct=default)
    {
        if(plan.Commands.Length!=1 || plan.Commands[0].Opcode!=0x91)throw new ArgumentException("Runtime feedback only.");
        // A hook approval's bounded 00 query may own this gate when the same hook requests RGB.
        // Wait before the first send only; never retry a transport operation or queue configuration.
        if(!RealBackendSelected || realDevice is null || !await gate.WaitAsync(600,ct))return false;
        using var linked=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime.Token);
        try
        {
            if(!enabled() || realDevice.Observation is not {IsLive:true,SessionId:{} session,Status:{} status}
                || session!=plan.Session || status.WorkMode!=(int)profile)return false;
            gate.Describe("Assistant lighting",plan.Session,realDevice.ActiveTransport,false);linked.CancelAfter(TimeSpan.FromSeconds(10));beforeSend();await realDevice.ExecuteControlsAsync(plan,e=>{record(e);if(e.Error is null && e.ResponseAt is not null)gate.Confirm(e.Operation);},linked.Token);return true;
        }
        catch{gate.Fail(false);throw;}
        finally{gate.Release();Changed?.Invoke();}
    }
    private async Task ReadCore(CancellationToken ct)
    {
        if(RealBackendSelected) { if(realDevice is null)throw new InvalidOperationException();await realDevice.RefreshAsync(ct);return; }
        EnsureConnected(); state.MoveTo(ConnectionState.ReadingConfiguration); Changed?.Invoke();
        tracker.Read(await device.ReadAsync(ct)); state.MoveTo(ConnectionState.Connected);
    }
    public Task WriteAsync(CancellationToken ct = default) => Run(WriteCore, true, ct);
    public Task WriteAndReadAsync(CancellationToken ct = default) => Run(async token =>
    {
        await WriteCore(token);
        await ReadCore(token);
    }, true, ct);
    private async Task WriteCore(CancellationToken token)
    {
        if(RealBackendSelected) throw new BleException("BleReadOnly","Physical configuration writes disabled.");
        EnsureConnected(); device.Capabilities.Validate(tracker.Draft);
        var session = device.Status.SessionId!.Value;
        var captured = tracker.BeginWrite(session, device.Identity, DateTimeOffset.UtcNow);
        state.MoveTo(ConnectionState.WritingConfiguration); Changed?.Invoke();
        await device.WriteAsync(captured.Configuration, token);
        tracker.AcceptWrite(session); state.MoveTo(ConnectionState.Connected);
    }
    private void EnsureConnected()
    {
        if (RealBackendSelected || State != ConnectionState.Connected) throw new InvalidOperationException("Device is not ready.");
    }
    private async Task Run(Func<CancellationToken, Task> operation, bool writing, CancellationToken ct, bool wait=false)
    {
        if (!await gate.WaitAsync(wait?Timeout.Infinite:0, ct)) { ErrorKey = "ErrorDeviceBusy"; Changed?.Invoke(); return; }
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(ct, lifetime.Token);
        try { gate.Describe(writing?"Simulator write":"Connection / telemetry",Device.Status.SessionId,RealBackendSelected?realDevice?.ActiveTransport:null,false);linked.CancelAfter(TimeSpan.FromSeconds(45));ErrorKey = null; await operation(linked.Token); logger.LogInformation("Device operation completed: {State}; {Sync}", State, tracker.State); }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            gate.Fail(false);
            var failure = ex as DeviceOperationException;
            ErrorKey = ex is Usb.UsbException usb ? usb.Key : ex is BleException ble ? ble.Key : ex is FormatException ? "BleInvalidResponse" : ex is OperationCanceledException ? "ErrorCancelled" : failure is null ? "ErrorNotReady" : "Error" + failure.Failure;
            if (writing && tracker.PendingWrite is not null) tracker.FailWrite(ex is OperationCanceledException || failure?.IsIndeterminate == true);
            if (writing && tracker.PendingWrite is null && tracker.State == SyncState.WriteAccepted) tracker.FailWrite(true);
            if (!writing) tracker.InvalidateSession();
            if (failure?.Failure == MockFailure.DeviceBusy && State is ConnectionState.WritingConfiguration or ConnectionState.ReadingConfiguration)
            { state.MoveTo(ConnectionState.Busy); Changed?.Invoke(); state.MoveTo(ConnectionState.Connected); }
            else if (Device.Status.SessionId is null) state.MoveTo(ConnectionState.Disconnected);
            else if (State is ConnectionState.WritingConfiguration or ConnectionState.ReadingConfiguration)
            {
                state.MoveTo(ConnectionState.Error);
                // An uncertain result needs an explicit disconnect/reconnect, not an automatic retry.
            }
            else if (State == ConnectionState.Connecting) state.MoveTo(ConnectionState.Error);
            logger.LogWarning("Device operation failed: {Error}; {State}", ErrorKey, State);
        }
        finally { gate.Release(); Changed?.Invoke(); }
    }
    public Task ReconnectAsync(CancellationToken ct=default)=>Run(async token=>
    {
        if(!RealBackendSelected || realDevice is null)throw new InvalidOperationException();
        state.MoveTo(ConnectionState.Disconnected);state.MoveTo(ConnectionState.Connecting);Changed?.Invoke();
        await realDevice.ReconnectAsync(token);state.MoveTo(ConnectionState.Connected);
    },false,ct);
    public Task SelectTransportAsync(PhysicalTransportKind kind)=>Run(async token=>
    {
        if(!RealBackendSelected || realDevice is null)throw new InvalidOperationException();
        await realDevice.SelectTransportAsync(kind);state.MoveTo(ConnectionState.Disconnected);tracker.InvalidateSession();
    },false,default,true);
    public void Dispose()
    {
        // In-flight continuations still release this managed gate after cancellation.
        // It never creates a wait handle; let it be collected after those operations finish.
        realDevice?.CancelCurrent();lifetime.Cancel(); lifetime.Dispose();
    }
}

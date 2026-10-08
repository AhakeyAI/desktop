using AhaKey.Device.Ble;
namespace AhaKey.Device;

// Bounded reconnect bursts for a selected device. The attachment supervisor
// schedules further attempts after cooldown; no setters or mock fallback.
public sealed class RealDeviceRuntime : IDisposable
{
    private readonly DeviceManager manager;
    private readonly object sync=new();
    private CancellationTokenSource? operation;
    private Task active=Task.CompletedTask;
    private bool stopped=true, disposed;
    private Guid? handledLoss;
    private DateTimeOffset retryAfter;
    private readonly TimeSpan recoveryInterval;
    public event Action? Changed;
    public bool Busy {get;private set;}
    public bool Reconnecting {get;private set;}
    public bool ExplicitlyDisconnected => stopped;
    public RealDeviceRuntime(DeviceManager manager,TimeSpan? recoveryInterval=null)
    {this.manager=manager;this.recoveryInterval=recoveryInterval??TimeSpan.FromSeconds(30);if(manager.RealDevice is {} real)real.Changed+=OnChanged;}
    // Retry only the selected device after transport loss; never infer a live
    // session from Windows pairing, or restart after an explicit disconnect.
    public Task RetryDisconnectedAsync()
    {
        lock(sync)
        {
            if(stopped||disposed||Busy||manager.Operations.Current is not null||manager.Operations.ShutdownRequested||DateTimeOffset.UtcNow<retryAfter||
               manager.RealDevice is not {ActiveTransport:PhysicalTransportKind.Bluetooth,Selected:not null,Observation.IsLive:false} real||
               real.Diagnostics.ErrorKey is not ("BleLinkLost" or "BleNativeFailure" or "BleQueryTimeout" or "BleAcquireTimeout" or "BleAcquireFailure" or "BleAdapterUnavailable" or "BleNotReady"))return Task.CompletedTask;
            retryAfter=DateTimeOffset.UtcNow+recoveryInterval;
            return ConnectAsync(true);
        }
    }
    public void SuspendRecovery() { lock(sync){stopped=true;} }
    public void ResumeRecovery() { lock(sync){if(!disposed)stopped=false;} }
    public Task StartAsync()=>manager.RealBackendSelected && manager.RealDevice is {ActiveTransport:PhysicalTransportKind.Bluetooth,Selected:not null} ? ConnectAsync(true) : Task.CompletedTask;
    public Task ConnectAsync(bool reconnect=false)
    {
        lock(sync)
        {
            if(disposed || Busy || !manager.RealBackendSelected || manager.RealDevice is null || (manager.RealDevice.ActiveTransport==PhysicalTransportKind.Bluetooth && manager.RealDevice.Selected is null))return active;
            stopped=false;Busy=true;Reconnecting=reconnect;operation=new();
            active=ConnectCore(operation,reconnect);return active;
        }
    }
    private async Task ConnectCore(CancellationTokenSource owner,bool reconnect)
    {
        // Yield so the assigned active task is available to cancellation/close callers.
        await Task.Yield();Changed?.Invoke();
        try {if(reconnect)await manager.ReconnectAsync(owner.Token);else await manager.ConnectAsync(owner.Token);}
        catch(Exception ex) {manager.RealDevice?.RecordError(ex);}
        finally
        {
            lock(sync){if(ReferenceEquals(operation,owner)){operation=null;Busy=false;Reconnecting=false;retryAfter=DateTimeOffset.UtcNow+recoveryInterval;}}
            owner.Dispose();Changed?.Invoke();
        }
    }
    private void OnChanged()
    {
        lock(sync)
        {
            var d=manager.RealDevice!.Diagnostics;
            if(!disposed && !stopped && !Busy && manager.RealBackendSelected && manager.RealDevice.ActiveTransport==PhysicalTransportKind.Bluetooth && d.ErrorKey=="BleLinkLost" && d.SessionId is {} id && handledLoss!=id)
            {handledLoss=id;_ = ConnectAsync(true);}
        }
        Changed?.Invoke();
    }
    public async Task DisconnectAsync()
    {
        Task pending;
        lock(sync){stopped=true;operation?.Cancel();pending=active;}
        manager.RealDevice?.CancelCurrent();
        await pending;await manager.DisconnectAsync();Changed?.Invoke();
    }
    public void Dispose()
    {lock(sync){disposed=true;stopped=true;operation?.Cancel();}if(manager.RealDevice is {} real)real.Changed-=OnChanged;}
    public async Task SelectTransportAsync(PhysicalTransportKind kind)
    {await DisconnectAsync();await manager.SelectTransportAsync(kind);Changed?.Invoke();}
}

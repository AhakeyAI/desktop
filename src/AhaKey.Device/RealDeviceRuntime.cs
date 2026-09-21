using AhaKey.Device.Ble;
namespace AhaKey.Device;

// One bounded reconnect burst per lost session. No discovery, polling, setters or mock fallback.
public sealed class RealDeviceRuntime : IDisposable
{
    private readonly DeviceManager manager;
    private readonly object sync=new();
    private CancellationTokenSource? operation;
    private Task active=Task.CompletedTask;
    private bool stopped=true, disposed;
    private Guid? handledLoss;
    public event Action? Changed;
    public bool Busy {get;private set;}
    public bool Reconnecting {get;private set;}
    public bool ExplicitlyDisconnected => stopped;
    public RealDeviceRuntime(DeviceManager manager)
    {this.manager=manager;if(manager.RealDevice is {} real)real.Changed+=OnChanged;}
    public void SuspendRecovery() { lock(sync){stopped=true;} }
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
            lock(sync){if(ReferenceEquals(operation,owner)){operation=null;Busy=false;Reconnecting=false;}}
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

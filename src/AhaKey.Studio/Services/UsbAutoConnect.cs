using AhaKey.Device;
using AhaKey.Device.Usb;
using System.Windows.Threading;
namespace AhaKey.Studio.Services;

// A read-only normal handshake once per attachment. Never runs during firmware
// ownership and never reapplies configuration or retries a rejected attachment.
public sealed class UsbAutoConnect : IDisposable
{
    private readonly DeviceManager manager;
    private readonly RealDeviceRuntime connections;
    private readonly FirmwareRuntime firmware;
    private readonly PhysicalControlRuntime controls;
    private readonly DispatcherTimer timer=new(){Interval=TimeSpan.FromMilliseconds(750)};
    private string? attemptedPath;
    private bool checking,disposed;
    public UsbAutoConnect(DeviceManager manager,RealDeviceRuntime connections,FirmwareRuntime firmware,PhysicalControlRuntime controls)
    {this.manager=manager;this.connections=connections;this.firmware=firmware;this.controls=controls;timer.Tick+=OnTick;}
    public async Task StartAsync(){await CheckAsync();if(!disposed)timer.Start();}
    private async void OnTick(object? sender,EventArgs e)=>await CheckAsync();
    private async Task CheckAsync()
    {
        if(disposed||checking||!manager.RealBackendSelected||firmware.Busy||firmware.Preparing||connections.Busy||controls.UsbOperationBusy||manager.Operations.Current is not null||manager.Operations.ShutdownRequested||manager.RealDevice?.Usb is null)return;
        checking=true;
        try
        {
            var real=manager.RealDevice;
            var selection=HidSelectionPolicy.Select(await new WindowsHidSessionFactory().EnumerateAsync(CancellationToken.None));
            if(disposed||firmware.Busy||firmware.Preparing)return;
            if(selection.Candidate is not {} candidate)
            {
                if(selection.ErrorKey=="UsbAmbiguous")return;
                var removed=attemptedPath is not null;attemptedPath=null;
                if(removed && real.ActiveTransport==PhysicalTransportKind.Usb && real.Selected is not null && !connections.ExplicitlyDisconnected)
                {
                    await connections.SelectTransportAsync(PhysicalTransportKind.Bluetooth);
                    if(!disposed&&!firmware.Busy&&!firmware.Preparing)await connections.ConnectAsync();
                }
                else if(!disposed&&!firmware.Busy&&!firmware.Preparing)await connections.RetryDisconnectedAsync();
                return;
            }
            if(attemptedPath==candidate.Path)return;
            // Consume the attachment before attempting the handshake. Explicit
            // disconnects and failures remain disconnected until unplug/replug.
            attemptedPath=candidate.Path;
            if(real.ActiveTransport==PhysicalTransportKind.Usb&&real.Observation.IsLive)return;
            if(firmware.Busy||firmware.Preparing||manager.Operations.Current is not null)return;
            await connections.SelectTransportAsync(PhysicalTransportKind.Usb);
            if(!disposed&&!firmware.Busy&&!firmware.Preparing)await connections.ConnectAsync();
        }
        catch(Exception ex)when(ex is not OutOfMemoryException){CrashEvidence.Record(ex,"USB auto-connect");}
        finally{checking=false;}
    }
    public void Dispose(){disposed=true;timer.Stop();timer.Tick-=OnTick;}
}


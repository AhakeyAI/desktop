using AhaKey.Core;
using AhaKey.Device.Ble;
using AhaKey.Protocol;
using AhaKey.Device.Usb;
namespace AhaKey.Device;

// This backend exposes telemetry, never a physical configuration snapshot.
public sealed class RealAhaKeyDevice : IAhaKeyDevice, IAsyncDisposable
{
    private readonly BleTransport transport;
    public UsbTransport? Usb {get;}
    public PhysicalTransportKind ActiveTransport {get;private set;}
    private IReadOnlyQueryTransport QueryTransport=>ActiveTransport==PhysicalTransportKind.Usb?Usb!:transport;
    public PhysicalObservation Observation=>QueryTransport.Observation;
    public FirmwareIdentity FirmwareIdentity=>FirmwareProtocols.Identify(Observation.Status,Observation.Capabilities);
    public IFirmwareProtocolAdapter ProtocolAdapter=>FirmwareProtocols.For(FirmwareIdentity.Dialect);
    public DeviceReadiness Readiness=>DeviceReadiness.From(Observation,Diagnostics.NativeConnected==true,Diagnostics.Subscribed,DateTimeOffset.UtcNow);
    public RealAhaKeyDevice(BleTransport transport,UsbTransport? usb=null)
    {this.transport=transport;Usb=usb;transport.Changed+=Notify;if(usb is not null)usb.Changed+=Notify;}
    private void Notify()=>Changed?.Invoke();
    public void CancelCurrent(){transport.CancelCurrent();Usb?.CancelCurrent();}
    public void RecordError(Exception ex){if(ActiveTransport==PhysicalTransportKind.Usb)Usb!.RecordError(ex);else transport.RecordError(ex);}
    // Invoked only after runtime intent and previous owner have stopped, under the manager gate.
    public async Task SelectTransportAsync(PhysicalTransportKind kind)
    {
        CancelCurrent();await gate.WaitAsync();
        try {await transport.DisconnectAsync();if(Usb is not null)await Usb.DisconnectAsync();if(kind==PhysicalTransportKind.Usb && Usb is null)throw new UsbException("UsbNotReady","USB is not registered.");ActiveTransport=kind;Notify();}
        finally {gate.Release();}
    }
    private readonly SemaphoreSlim gate=new(1,1);
    public BleDeviceInfo? Selected {get;set;}
    public BleTransport Transport=>transport;
    public BleDiagnostics Diagnostics=>transport.Diagnostics;
    public DeviceIdentity Identity=>new(ActiveTransport==PhysicalTransportKind.Usb?"AhaKey USB device":Selected?.Name??"AhaKey", Firmware, false);
    private string Firmware=>FirmwareIdentity.ReportedVersion??"Unknown";
    // Local draft validation only; not proof of supported physical writes.
    public DeviceCapabilities Capabilities {get;}=new(true);
    public DeviceStatus Status=>new(Observation.IsLive?ConnectionState.Connected:ConnectionState.Disconnected,
        Observation.IsLive?Observation.Status?.Battery:null,
        Observation.IsLive?Observation.Status?.Confirmation:null,Observation.IsLive?Observation.SessionId:null);
    public event Action? Changed;
    public Task<IReadOnlyList<BleDeviceInfo>> DiscoverAsync(CancellationToken ct=default)=>transport.DiscoverAsync(ct);
    public async Task ConnectAsync(CancellationToken cancellationToken=default)
    {
        await gate.WaitAsync(cancellationToken);
        try {await ConnectCore(cancellationToken);}
        finally {gate.Release();}
    }
    private async Task ConnectCore(CancellationToken ct)
    {
        try
        {
            if(ActiveTransport==PhysicalTransportKind.Usb)await Usb!.OpenAsync(ct);
            else await transport.OpenAsync(Selected??throw new BleException("BleSelectDevice","Select a discovered device first."),ct);
            await ReadPair(ct);
        }
        catch(Exception ex){await DisconnectAsync();RecordError(ex);throw;}
    }
    private async Task ReadPair(CancellationToken ct)
    {
        var active=QueryTransport;
        var status=await active.QueryFrameAsync(ReadOnlyQuery.PhysicalStatus,ct);
        active.AcceptStatus(status,AhaKeyProtocol.DecodeStatus(status.Rx.AsSpan()));
        var caps=await active.QueryFrameAsync(ReadOnlyQuery.Capabilities,ct);
        active.AcceptCapabilities(caps,AhaKeyProtocol.DecodeCapabilities(caps.Rx.AsSpan()));
    }
    public async Task RefreshAsync(CancellationToken ct=default)
    {
        await gate.WaitAsync(ct);
        try {await ReadPair(ct);}
        catch(Exception ex){await DisconnectAsync();RecordError(ex);throw;}
        finally {gate.Release();}
    }
    public async Task<PhysicalObservation?> RefreshApprovalStatusAsync(CancellationToken ct)
    {
        if (!await gate.WaitAsync(0, ct)) return null;
        try
        {
            var active = QueryTransport;
            var before = active.Observation;
            if (!before.IsLive || before.SessionId is null) return null;
            var query = await active.QueryFrameAsync(ReadOnlyQuery.PhysicalStatus, ct);
            if (query.SessionId != before.SessionId || !active.Observation.IsLive || active.Observation.SessionId != before.SessionId) return null;
            active.AcceptStatus(query, AhaKeyProtocol.DecodeStatus(query.Rx.AsSpan()));
            return active.Observation;
        }
        finally { gate.Release(); }
    }
    public async Task<System.Collections.Immutable.ImmutableArray<byte>> ReadConfigAsync(byte resource,byte index,Action<PhysicalCommandEvidence> record,CancellationToken ct)
    {
        if(!await gate.WaitAsync(0,ct))throw new InvalidOperationException("Device busy.");
        try{if(ActiveTransport!=PhysicalTransportKind.Usb||Usb is null)throw new InvalidOperationException("USB read required.");return await Usb.ReadConfigAsync(resource,index,record,ct);}
        finally{gate.Release();}
    }
    public async Task UploadDisplayAsync(ApprovedDisplayUpload approval,Action<DisplayTransferEvidence> record,Action<DisplayResponseEvidence> responseRecord,CancellationToken ct)
    {
        if(!await gate.WaitAsync(0,ct))throw new InvalidOperationException("Device busy.");
        try{if((approval.Modern is null?FirmwareIdentity.Dialect!=FirmwareDialect.LegacyWindows:!new DeviceFeatureCatalog(FirmwareIdentity,FeatureTransport.Usb,new()).CanUploadDisplay(approval.Modern.Transfer.Profile,approval.Modern.Transfer.Asset,approval.Modern.Transfer.FrameCount).Available) || ActiveTransport!=PhysicalTransportKind.Usb || Usb is null)throw new InvalidOperationException("Shipping Display requires the attested legacy USB route.");await Usb.UploadDisplayAsync(approval,record,responseRecord,ct);}
        finally{gate.Release();}
    }
    public async Task ExecuteControlsAsync(ApprovedControlPlan plan,Action<PhysicalCommandEvidence> record,CancellationToken ct)
    {
        if(!await gate.WaitAsync(0,ct))throw new InvalidOperationException("Device busy.");
        try
        {
            if(Observation is not {IsLive:true,SessionId:{} session})throw new InvalidOperationException("No live physical session.");
            var commands=plan.Begin(session);
            foreach(var command in commands)ProtocolAdapter.ValidateControl(command.Command);
            var target=QueryTransport as IPhysicalControlTransport??throw new NotSupportedException();
            foreach(var command in commands)
            {
                ct.ThrowIfCancellationRequested();
                try{record(await target.SendControlAsync(command,ct));}
                catch(PhysicalControlException ex){record(ex.Evidence);throw;}
                // Retained Java sequencing. No retry and no save after a failed preceding write.
                await Task.Delay(20,ct);
            }
            if(commands.Any(c=>c.Command.Opcode==4))await Task.Delay(250,ct);
        }
        finally{gate.Release();}
    }
    public async Task ReconnectAsync(CancellationToken ct=default)
    {
        CancelCurrent();await gate.WaitAsync(ct);
        try
        {
            if(ActiveTransport==PhysicalTransportKind.Usb){await ConnectCore(ct);return;}
            for(int attempt=1;attempt<=2;attempt++)
            {
                ct.ThrowIfCancellationRequested();transport.Reconnecting(attempt);
                try {await ConnectCore(ct);return;}
                catch(Exception ex) when(attempt<2 && ex is not OperationCanceledException && !ct.IsCancellationRequested)
                {await Task.Delay(300,ct);}
            }
        }
        finally {gate.Release();}
    }
    public async Task DisconnectAsync(CancellationToken cancellationToken=default)
    {CancelCurrent();await transport.DisconnectAsync();if(Usb is not null)await Usb.DisconnectAsync();}
    public Task<ConfigurationSnapshot> ReadAsync(CancellationToken cancellationToken=default)=>throw new BleException("BleDraftOnly","Physical configuration reads are outside Phase 3.");
    public Task WriteAsync(DeviceConfiguration configuration,CancellationToken cancellationToken=default)=>throw new BleException("BleReadOnly","Physical configuration writes are disabled.");
    public async ValueTask DisposeAsync(){await transport.DisposeAsync();if(Usb is not null)await Usb.DisposeAsync();}
}

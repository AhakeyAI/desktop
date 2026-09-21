using System.Collections.Immutable;
using AhaKey.Protocol;
namespace AhaKey.Device.Ble;
// Serializes full query transactions as well as individual awaited GATT command writes.
public sealed partial class BleTransport(IWindowsGattSessionFactory factory,GattContract contract) : IAsyncDisposable, IReadOnlyQueryTransport, IPhysicalControlTransport
{
    public PhysicalObservation Observation { get { var d=Diagnostics;return new(PhysicalTransportKind.Bluetooth,d.SessionId,d.IsLive,d.PhysicalStatus,d.Capabilities,d.LastStatusQuery?.ResponseAt,d.ErrorKey); } }
    public async Task<PhysicalQueryEvidence> QueryFrameAsync(ReadOnlyQuery command,CancellationToken ct)
    {var q=await QueryAsync(command,ct);return new(PhysicalTransportKind.Bluetooth,q.SessionId,q.Command,q.WriteStartedAt,q.WriteCompletedAt,q.ResponseAt,q.Tx,q.Rx);}
    public void AcceptStatus(PhysicalQueryEvidence query,PhysicalStatus status)
    {if(Diagnostics.LastQuery is {} q && q.SessionId==query.SessionId && q.ResponseAt==query.ResponseAt)PublishStatus(q,status);}
    public void AcceptCapabilities(PhysicalQueryEvidence query,PhysicalCapabilities caps)
    {if(Diagnostics.LastQuery is {} q && q.SessionId==query.SessionId && q.ResponseAt==query.ResponseAt)PublishCapabilities(q,caps);}
    private readonly object sync=new();
    private readonly SemaphoreSlim operations=new(1,1);
    private IWindowsGattSession? session;
    private CancellationTokenSource? sessionCancellation;
    private CancellationTokenSource? discoveryCancellation;
    private long generation;
    private long discoveryGeneration;
    private PendingQuery? pending;
    private BleDiagnostics diagnostics=new();
    private bool disposed;
    private sealed class PendingQuery(Guid id,ReadOnlyQuery command)
    {
        public Guid Id {get;}=id; public ReadOnlyQuery Command {get;}=command;
        public DateTimeOffset StartedAt {get;set;}
        public TaskCompletionSource<BleNotification> Response {get;}=new(TaskCreationOptions.RunContinuationsAsynchronously);
    }
    public TimeSpan QueryTimeout {get;init;}=TimeSpan.FromSeconds(4);
    public TimeSpan NativeTimeout {get;init;}=TimeSpan.FromSeconds(20);
    public TimeSpan RetryDelay {get;init;}=TimeSpan.FromMilliseconds(200);
    public BleDiagnostics Diagnostics {get{lock(sync)return diagnostics;}}
    public event Action? Changed;
    public event Action<BleHistory>? OperationalEvent;
    private void Update(Func<BleDiagnostics,BleDiagnostics> change,string? evt=null,string? detail=null)
    {
        lock(sync)
        {
            diagnostics=change(diagnostics) with{ObservedAt=DateTimeOffset.UtcNow};
            if(evt is not null) diagnostics=diagnostics with{History=diagnostics.History.Add(new(DateTimeOffset.UtcNow,diagnostics.SessionId,evt,detail??"")).TakeLast(64).ToImmutableArray()};
        }
        Changed?.Invoke();
        if(evt is not null)OperationalEvent?.Invoke(new(DateTimeOffset.UtcNow,Diagnostics.SessionId,evt,detail??""));
    }
    private void EnsureCurrent(long ticket,CancellationToken ct)
    {ct.ThrowIfCancellationRequested();lock(sync){if(disposed || generation!=ticket || session is null)throw new OperationCanceledException(ct);}}
    public async Task<IReadOnlyList<BleDeviceInfo>> DiscoverAsync(CancellationToken ct=default)
    {
        CancellationTokenSource owner;long ticket;
        lock(sync){ObjectDisposedException.ThrowIf(disposed,this);discoveryCancellation?.Cancel();owner=CancellationTokenSource.CreateLinkedTokenSource(ct);discoveryCancellation=owner;ticket=++discoveryGeneration;}
        await using var scan=factory.Create(Guid.NewGuid());
        Update(d=>d with{Stage=BleStage.Discovering,Error=null,ErrorKey=null},"Discovering");
        try
        {
            var devices=await scan.DiscoverAsync(TimeSpan.FromSeconds(8),owner.Token);
            lock(sync){if(ticket!=discoveryGeneration || owner.IsCancellationRequested || disposed)throw new OperationCanceledException(owner.Token);}
            lock(sync){if(ticket!=discoveryGeneration)throw new OperationCanceledException(owner.Token);Update(d=>d with{Adapter=scan.Adapter,Stage=d.IsLive?BleStage.Ready:BleStage.Disconnected},"DiscoveryCompleted",devices.Count.ToString());}return devices;
        }
        catch(Exception ex) when(ex is not OperationCanceledException) {lock(sync){if(ticket==discoveryGeneration)RecordError(ex);}throw;}
        finally {lock(sync){if(ReferenceEquals(discoveryCancellation,owner)){discoveryCancellation=null;if(diagnostics.Stage==BleStage.Discovering)Update(d=>d with{Stage=d.IsLive?BleStage.Ready:BleStage.Disconnected});}}owner.Dispose();}
    }
    public void CancelCurrent()
    {lock(sync){discoveryCancellation?.Cancel();++discoveryGeneration;sessionCancellation?.Cancel();pending?.Response.TrySetCanceled();}}
    public async Task OpenAsync(BleDeviceInfo selected,CancellationToken ct=default)
    {
        await operations.WaitAsync(ct);
        try
        {
            ObjectDisposedException.ThrowIf(disposed,this);
            await CloseCore();
            var owner=CancellationTokenSource.CreateLinkedTokenSource(ct);owner.CancelAfter(NativeTimeout);
            var active=factory.Create(Guid.NewGuid());long ticket;
            lock(sync){session=active;sessionCancellation=owner;ticket=++generation;}
            active.ConnectionChanged+=OnNativeConnection;
            Update(d=>d with{Device=selected,SessionId=active.Id,Stage=BleStage.AcquiringLink,Subscribed=false,IsLive=false,NativeConnected=null,Catalog=[],PhysicalStatus=null,Capabilities=null,LastDataAt=null,LastStatusQuery=null,LastQuery=null,LastTx=[],LastRx=[],Error=null,ErrorKey=null},"AcquiringLink");
            try
            {
                await active.AcquireAsync(selected.Id,owner.Token);EnsureCurrent(ticket,owner.Token);
                Update(d=>d with{Adapter=active.Adapter,NativeConnected=active.NativeConnected,Stage=BleStage.DiscoveringGatt},"DiscoveringGatt");
                var catalog=await active.DiscoverGattAsync(owner.Token);EnsureCurrent(ticket,owner.Token);
                Update(d=>d with{Catalog=catalog,NativeConnected=active.NativeConnected},"GattCatalog",$"{catalog.Length} services");contract.Validate(catalog);
                Update(d=>d with{Stage=BleStage.Subscribing},"Subscribing");
                for(int attempt=1;attempt<=3;attempt++)
                {
                    var result=await active.SubscribeAsync(contract.Service,contract.Notify,OnNotification,owner.Token);EnsureCurrent(ticket,owner.Token);
                    Update(d=>d with{LastGattResult=result},"CCCD",$"attempt={attempt}; {result.Status}; ATT={result.ProtocolError}");
                    if(result.Success) break;
                    if(attempt==3 || result.Status!=GattResultStatus.Unreachable) result.RequireSuccess("CCCD");
                    await Task.Delay(RetryDelay*attempt,owner.Token);
                }
                owner.CancelAfter(Timeout.InfiniteTimeSpan);
                Update(d=>d with{Subscribed=true,NativeConnected=active.NativeConnected},"Subscribed");
            }
            catch(Exception ex) {Update(d=>d with{Adapter=active.Adapter});await CloseCore();RecordError(ex);throw;}
        }
        finally {operations.Release();}
    }
    private void OnNativeConnection(Guid id,bool connected)
    {
        lock(sync)
        {
            if(disposed || session?.Id!=id || sessionCancellation?.IsCancellationRequested==true)return;
            diagnostics=diagnostics with{NativeConnected=connected,Adapter=session.Adapter};
            if(!connected && diagnostics.Stage is BleStage.Ready or BleStage.ReadingStatus or BleStage.ReadingCapabilities)
            {sessionCancellation?.Cancel();pending?.Response.TrySetException(new BleException("BleLinkLost","Native BLE link was lost."));diagnostics=diagnostics with{Stage=BleStage.Error,IsLive=false,Subscribed=false,ErrorKey="BleLinkLost",Error="Native BLE link lost; explicit reconnect required."};}
        }
        Changed?.Invoke();
        if(!connected) _=CloseLostSessionAsync(id);
    }
    private async Task CloseLostSessionAsync(Guid id)
    {
        await operations.WaitAsync().ConfigureAwait(false);
        try {if(session?.Id==id && sessionCancellation?.IsCancellationRequested==true){await CloseCore().ConfigureAwait(false);RecordError(new BleException("BleLinkLost","Native BLE link lost; explicit reconnect required."));}}
        finally {operations.Release();}
    }
    private void OnNotification(BleNotification notification)
    {
        lock(sync)
        {
            if(disposed || session?.Id!=notification.SessionId || sessionCancellation?.IsCancellationRequested==true)return;
            diagnostics=diagnostics with{LastRx=notification.Bytes};
            // Firmware has no request IDs. Buffer a current-session response after TX starts; publish only after successful awaited TX.
            if(pending is {} request && request.Id==notification.SessionId && notification.ArrivedAt>=request.StartedAt && AhaKeyProtocol.IsFrame(notification.Bytes.AsSpan(),request.Command))
                request.Response.TrySetResult(notification);
        }
        Changed?.Invoke();
    }
    public async Task<QueryEvidence> QueryAsync(ReadOnlyQuery command,CancellationToken ct=default)
    {
        var frame=AhaKeyProtocol.Query(command);await operations.WaitAsync(ct);
        try
        {
            var active=session??throw new BleException("BleNotReady","BLE session is absent.");
            using var query=CancellationTokenSource.CreateLinkedTokenSource(ct,sessionCancellation!.Token);query.CancelAfter(QueryTimeout);
            var ticket=generation;var request=new PendingQuery(active.Id,command){StartedAt=DateTimeOffset.UtcNow};
            lock(sync){if(!diagnostics.Subscribed)throw new BleException("BleNotReady","Notifications are not subscribed.");pending=request;}
            var started=request.StartedAt;
            Update(d=>d with{Stage=command==ReadOnlyQuery.PhysicalStatus?BleStage.ReadingStatus:BleStage.ReadingCapabilities,LastTx=frame},"TX",Convert.ToHexString(frame.AsSpan()));
            try
            {
                var result=await active.WriteCommandAsync(contract.Service,contract.Command,frame,query.Token);
                var completed=DateTimeOffset.UtcNow;EnsureCurrent(ticket,query.Token);
                Update(d=>d with{LastGattResult=result},"GattWrite",$"{result.Status}; ATT={result.ProtocolError}");result.RequireSuccess("WriteWithResponse");
                var response=await request.Response.Task.WaitAsync(query.Token);EnsureCurrent(ticket,query.Token);
                var evidence=new QueryEvidence(active.Id,command,started,completed,response.ArrivedAt,frame,response.Bytes,result);
                Update(d=>d with{LastQuery=evidence},"RX",$"{Convert.ToHexString(response.Bytes.AsSpan())}; latency={evidence.LatencyMs:F1}ms");return evidence;
            }
            catch(Exception ex)
            {
                // A timeout quarantines the session: no same-command retry may consume a late response.
                await CloseCore();
                var error=ex is OperationCanceledException && !ct.IsCancellationRequested?new BleException("BleQueryTimeout","Query cancelled or timed out; session disposed."):ex;
                RecordError(error);throw error;
            }
            finally {lock(sync){if(ReferenceEquals(pending,request))pending=null;}}
        }
        finally {operations.Release();}
    }
    public void PublishStatus(QueryEvidence query,PhysicalStatus status)
    {lock(sync){if(session?.Id!=query.SessionId || sessionCancellation?.IsCancellationRequested==true)return;Update(d=>d with{PhysicalStatus=status,LastDataAt=query.ResponseAt,LastStatusQuery=query});}}
    public void PublishCapabilities(QueryEvidence query,PhysicalCapabilities caps)
    {lock(sync){if(session?.Id!=query.SessionId || sessionCancellation?.IsCancellationRequested==true)return;Update(d=>d with{Capabilities=caps,LastDataAt=query.ResponseAt,Stage=BleStage.Ready,IsLive=true,NativeConnected=session!.NativeConnected},"Ready");}}
    public void Reconnecting(int attempt)=>Update(d=>d with{Stage=BleStage.Reconnecting,ReconnectAttempt=attempt,IsLive=false},"Reconnect",attempt.ToString());
    public void RecordError(Exception ex)=>Update(d=>d with{Stage=BleStage.Error,IsLive=false,ErrorKey=ex is BleException ble?ble.Key:ex is FormatException?"BleInvalidResponse":ex is OperationCanceledException?"ErrorCancelled":"BleNativeFailure",Error=ex is BleException?ex.Message:$"{ex.GetType().Name}; HRESULT=0x{ex.HResult:X8}"},"Error",ex is BleException b?b.Key:ex.GetType().Name);
    public async Task DisconnectAsync()
    {
        CancelCurrent();await operations.WaitAsync();
        try{await CloseCore();}finally{operations.Release();}
    }
    private async Task CloseCore()
    {
        IWindowsGattSession? old;CancellationTokenSource? cancel;
        lock(sync){old=session;session=null;cancel=sessionCancellation;sessionCancellation=null;++generation;pending?.Response.TrySetCanceled();pending=null;}
        cancel?.Cancel();
        if(old is not null){old.ConnectionChanged-=OnNativeConnection;Update(d=>d with{Stage=BleStage.Disconnecting,IsLive=false,Subscribed=false},"Disconnecting");await old.DisposeAsync();Update(d=>d with{LastTeardownResult=old.TeardownResult},"CCCDUnsubscribe",old.TeardownResult?.Status.ToString()??"Unavailable");}
        cancel?.Dispose();Update(d=>d with{Stage=BleStage.Disconnected,IsLive=false,Subscribed=false,NativeConnected=false},"Disconnected");
    }
    public async ValueTask DisposeAsync(){lock(sync){if(disposed)return;disposed=true;}await DisconnectAsync().ConfigureAwait(false);}
}

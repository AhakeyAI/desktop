using System.Collections.Immutable;
using System.Text.Json;
using AhaKey.Protocol;
namespace AhaKey.Device.Usb;

public sealed partial class UsbTransport(IWindowsHidSessionFactory factory) : IReadOnlyQueryTransport, IAsyncDisposable, IPhysicalControlTransport
{
    private readonly SemaphoreSlim operations=new(1,1);
    private readonly object sync=new();
    private IWindowsHidSession? session;
    private CancellationTokenSource? lifetime;
    private UsbDiagnostics diagnostics=new();
    private readonly UsbFrameAccumulator accumulator=new(includeDisplayReads:true,includeControlAcks:true,includeDisplayWrites:true,includeConfigReads:true);
    private Pending? pending;
    private bool disposed;
    private sealed class Pending(Guid id, ReadOnlyQuery command, DateTimeOffset start)
    {
        public Guid Id {get;}=id;
        public ReadOnlyQuery Command {get;}=command;
        public DateTimeOffset Start {get;}=start;
        public List<ImmutableArray<byte>> Reports {get;}=[];
        public TaskCompletionSource<(DateTimeOffset At,ImmutableArray<byte> Frame)> Response {get;}=new(TaskCreationOptions.RunContinuationsAsynchronously);
    }
    public TimeSpan QueryTimeout {get;init;}=TimeSpan.FromSeconds(4);
    public UsbDiagnostics Diagnostics {get {lock(sync)return diagnostics;}}
    public PhysicalObservation Observation {get {var d=Diagnostics;return new(PhysicalTransportKind.Usb,d.SessionId,d.IsLive,d.Status,d.Capabilities,d.StatusAt,d.ErrorKey);}}
    public event Action? Changed;
    public event Action<UsbHistory>? OperationalEvent;
    private void Update(Func<UsbDiagnostics,UsbDiagnostics> change,string? evt=null,string detail="")
    {
        UsbHistory? entry=null;
        lock(sync)
        {
            diagnostics=change(diagnostics);
            if(evt is not null){entry=new(DateTimeOffset.UtcNow,diagnostics.SessionId,evt,detail);diagnostics=diagnostics with {History=diagnostics.History.Add(entry).TakeLast(64).ToImmutableArray()};}
        }
        if(evt!="InputReport")Changed?.Invoke();if(entry is not null)OperationalEvent?.Invoke(entry);
    }
    public async Task<HidSelection> DiscoverAsync(CancellationToken ct=default)
    {
        var candidates=await factory.EnumerateAsync(ct);var selection=HidSelectionPolicy.Select(candidates);
        Update(d=>d with {Candidates=candidates,ErrorKey=selection.ErrorKey,Error=null},"Enumeration",$"candidates={candidates.Count}; selection={selection.ErrorKey??"identified"}");
        return selection;
    }
    public async Task OpenAsync(CancellationToken ct=default)
    {
        await operations.WaitAsync(ct);
        try
        {
            ObjectDisposedException.ThrowIf(disposed,this);await CloseCore();
            var selection=await DiscoverAsync(ct);
            var selected=selection.Candidate??throw new UsbException(selection.ErrorKey!,"No unique verified HID collection.");
            var active=factory.Create(Guid.NewGuid());var owner=CancellationTokenSource.CreateLinkedTokenSource(ct);
            lock(sync){session=active;lifetime=owner;accumulator.Clear();}
            Update(d=>new UsbDiagnostics {SessionId=active.Id,Selected=selected,Candidates=d.Candidates,Stage="Opening",History=d.History},"Opening");
            try
            {
                await active.OpenAsync(selected,OnInput,OnFailure,owner.Token);owner.Token.ThrowIfCancellationRequested();
                Update(d=>d with {ReaderRunning=active.ReaderRunning,Stage="ReadyToQuery"},"ReaderStarted");
            }
            catch(Exception ex){await CloseCore();RecordError(ex);throw;}
        }
        catch(Exception ex){RecordError(ex);throw;}
        finally {operations.Release();}
    }
    private void OnFailure(Guid id,Exception ex)
    {
        lock(sync){if(session?.Id!=id || lifetime?.IsCancellationRequested!=false)return;pending?.Response.TrySetException(ex);}
        RecordError(ex);_ = CloseFailedAsync(id);
    }
    private async Task CloseFailedAsync(Guid id)
    {
        await operations.WaitAsync().ConfigureAwait(false);
        try{if(session?.Id==id){await CloseCore();RecordError(new UsbException("UsbLinkLost","USB reader stopped; reconnect manually."));}}
        finally{operations.Release();}
    }
    private void OnInput(HidInput input)
    {
        lock(sync)
        {
            if(session?.Id!=input.SessionId || lifetime?.IsCancellationRequested!=false)return;
            Update(d=>d with{LastInput=input.Report},"InputReport",Convert.ToHexString(input.Report.AsSpan()));
            try
            {
                if(pending is {} p && input.At>=p.Start && p.Reports.Count<64)p.Reports.Add(input.Report);
                foreach(var frame in accumulator.FeedReport(input.Report.AsSpan()))
                {
                    if(pending is {} request && request.Id==input.SessionId && input.At>=request.Start && AhaKeyProtocol.IsFrame(frame.AsSpan(),request.Command))
                        request.Response.TrySetResult((input.At,frame));
                }
            }
            catch(Exception ex){pending?.Response.TrySetException(ex);}
        }
    }
    public async Task<PhysicalQueryEvidence> QueryFrameAsync(ReadOnlyQuery command,CancellationToken ct)
    {
        var report=UsbReportCodec.EncodeQuery(command);var frame=AhaKeyProtocol.Query(command);
        await operations.WaitAsync(ct);
        try
        {
            var active=session??throw new UsbException("UsbNotReady","USB session absent.");
            using var query=CancellationTokenSource.CreateLinkedTokenSource(ct,lifetime!.Token);query.CancelAfter(QueryTimeout);
            var request=new Pending(active.Id,command,DateTimeOffset.UtcNow);
            lock(sync){accumulator.Clear();pending=request;}
            Update(d=>d with {LastOutput=report,Stage="Querying"},"OutputReport",$"command={(byte)command:X2}; bytes={Convert.ToHexString(report.AsSpan())}; size={report.Length}");
            try
            {
                var result=await active.WriteAsync(report,query.Token);var completed=DateTimeOffset.UtcNow;
                Update(d=>d with {LastWriteResult=result},"WriteResult",$"success={result.Success}; bytes={result.BytesWritten}; error={result.Error}");
                if(!result.Success || result.BytesWritten!=report.Length)throw new UsbException("UsbWriteFailed",$"Native HID write success={result.Success}; bytes={result.BytesWritten}/{report.Length}; error={result.Error}. No fallback/retry.");
                var response=await request.Response.Task.WaitAsync(query.Token);query.Token.ThrowIfCancellationRequested();
                if(session?.Id!=active.Id)throw new OperationCanceledException();
                ImmutableArray<ImmutableArray<byte>> inputs;lock(sync)inputs=request.Reports.ToImmutableArray();
                var evidence=new UsbQueryEvidence(active.Id,command,request.Start,completed,response.At,frame,report,result,inputs,response.Frame);
                Update(d=>d with {LastQuery=evidence},"QueryEvidence",JsonSerializer.Serialize(evidence));
                return new(PhysicalTransportKind.Usb,active.Id,command,request.Start,completed,response.At,frame,response.Frame);
            }
            catch(Exception ex)
            {
                await CloseCore();var error=ex is OperationCanceledException && !ct.IsCancellationRequested?new UsbException("UsbTimeout","USB query timed out; session quarantined, no automatic retry."):ex;
                RecordError(error);throw error;
            }
            finally {lock(sync){if(ReferenceEquals(pending,request))pending=null;}}
        }
        finally{operations.Release();}
    }
    public void AcceptStatus(PhysicalQueryEvidence query,PhysicalStatus status)
    {lock(sync){if(session?.Id==query.SessionId && lifetime?.IsCancellationRequested==false)Update(d=>d with {Status=status,StatusAt=query.ResponseAt,LastStatusQuery=d.LastQuery});}}
    public void AcceptCapabilities(PhysicalQueryEvidence query,PhysicalCapabilities caps)
    {lock(sync){if(session?.Id==query.SessionId && lifetime?.IsCancellationRequested==false)Update(d=>d with {Capabilities=caps,IsLive=true,Stage="Ready"},"Ready");}}
    public void RecordError(Exception ex)=>Update(d=>d with {IsLive=false,Stage="Error",ErrorKey=ex is UsbException u?u.Key:ex is OperationCanceledException?"ErrorCancelled":"UsbReadFailed",Error=ex is UsbException?ex.Message:ex.GetType().Name},"Error",ex is UsbException u?u.Key:ex.GetType().Name);
    public void CancelCurrent(){lock(sync){lifetime?.Cancel();session?.Cancel();pending?.Response.TrySetCanceled();}}
    public async Task DisconnectAsync()
    {CancelCurrent();await operations.WaitAsync();try{await CloseCore();}finally{operations.Release();}}
    private async Task CloseCore()
    {
        IWindowsHidSession? old;CancellationTokenSource? cancel;
        lock(sync){old=session;session=null;cancel=lifetime;lifetime=null;pending?.Response.TrySetCanceled();pending=null;accumulator.Clear();}
        cancel?.Cancel();if(old is not null){old.Cancel();await old.DisposeAsync().ConfigureAwait(false);}
        cancel?.Dispose();Update(d=>d with {IsLive=false,ReaderRunning=false,Stage="Disconnected"},"Closed","reader stopped; handles released");
    }
    public async ValueTask DisposeAsync(){if(disposed)return;disposed=true;await DisconnectAsync();}
}

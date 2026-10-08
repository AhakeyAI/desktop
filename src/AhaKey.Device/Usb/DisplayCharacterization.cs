using System.Collections.Immutable;
using System.Threading.Channels;
using AhaKey.Protocol;
namespace AhaKey.Device.Usb;

public sealed class DisplayQueryEvidence
{
    public required int Sequence {get;init;}
    public required Guid SessionId {get;init;}
    public required string LogicalTx {get;init;}
    public required string OutputReport {get;init;}
    public int NativeWriteSize=>65;
    public DateTimeOffset WriteStartedAt {get;set;}
    public DateTimeOffset? WriteCompletedAt {get;set;}
    public DateTimeOffset? ResponseAt {get;set;}
    public double? LatencyMs=>ResponseAt is {} at?(at-WriteStartedAt).TotalMilliseconds:null;
    public HidWriteResult? NativeResult {get;set;}
    public List<string> InputReports {get;}=[];
    public string? Frame {get;set;}
    public int? FrameLength=>Frame?.Length/2;
    public DisplayReadResponse Response {get;set;}=new(DisplayResponseKind.UNKNOWN);
    public string? Error {get;set;}
}
public sealed class DisplayCharacterizationResult
{
    public string PhysicalUnit=>"AD1E (explicit user identity; USB name is neutral)";
    public Guid SessionId {get;init;}
    public List<DisplayQueryEvidence> Queries {get;}=[];
    public bool TeardownCompleted {get;set;}
    public bool ReaderStopped {get;set;}
    public DateTimeOffset? ClosedAt {get;set;}
    public string? RunError {get;set;}
}

// Dedicated USB-only run. No DeviceManager, BLE, local draft or normal UI capability mutation.
public sealed class DisplayCharacterization(IWindowsHidSessionFactory factory)
{
    private int started;
    public TimeSpan Timeout {get;init;}=TimeSpan.FromSeconds(4);
    public bool DefaultBindings {get;init;}
    public Action<string,object>? Trace {get;init;}
    public async Task<DisplayCharacterizationResult> RunAsync(HidCandidate candidate,CancellationToken ct=default)
    {
        if(Interlocked.Exchange(ref started,1)!=0)throw new InvalidOperationException("Characterization already attempted; no retry.");
        HidSelectionPolicy.Require(candidate);
        var result=new DisplayCharacterizationResult{SessionId=Guid.NewGuid()};var guard=new DisplayCharacterizationGuard(DefaultBindings);
        var channel=Channel.CreateBounded<HidInput>(128);
        var session=factory.Create(result.SessionId);
        try
        {
            await session.OpenAsync(candidate,input=>
            {
                if(input.SessionId!=result.SessionId)return;
                Trace?.Invoke("Input",new{input.SessionId,input.At,Report=Convert.ToHexString(input.Report.AsSpan())});
                if(!channel.Writer.TryWrite(input))channel.Writer.TryComplete(new IOException("Bounded input queue exceeded."));
            },(id,ex)=>{if(id==result.SessionId)channel.Writer.TryComplete(ex);},ct);
            Trace?.Invoke("Opened",new{result.SessionId,session.ReaderRunning});
            for(int i=0;i<guard.QueryCount;i++)
            {
                var request=guard.Request(i);var report=guard.Report(i);guard.Consume(report.AsSpan());
                var q=new DisplayQueryEvidence{Sequence=i,SessionId=result.SessionId,LogicalTx=Convert.ToHexString(request.AsSpan()),OutputReport=Convert.ToHexString(report.AsSpan()),WriteStartedAt=DateTimeOffset.UtcNow};
                result.Queries.Add(q);Trace?.Invoke("OutputAttempt",q);
                using var timeout=CancellationTokenSource.CreateLinkedTokenSource(ct);timeout.CancelAfter(Timeout);
                var accumulator=new UsbFrameAccumulator(includeDisplayReads:true);bool unexpected=false;
                try
                {
                    q.NativeResult=await session.WriteAsync(report,timeout.Token);q.WriteCompletedAt=DateTimeOffset.UtcNow;
                    Trace?.Invoke("WriteResult",new{q.Sequence,q.NativeResult,q.WriteCompletedAt});
                    if(!q.NativeResult.Success || q.NativeResult.BytesWritten!=65)throw new IOException("Native write failed/partial; sequence stopped, no retry.");
                    while(q.Frame is null)
                    {
                        var input=await channel.Reader.ReadAsync(timeout.Token);
                        if(input.At<q.WriteStartedAt)continue;
                        q.InputReports.Add(Convert.ToHexString(input.Report.AsSpan()));
                        foreach(var frame in accumulator.FeedReport(input.Report.AsSpan()))
                        {
                            if(frame[2]!=request[2]){unexpected=true;continue;}
                            q.Frame=Convert.ToHexString(frame.AsSpan());q.ResponseAt=input.At;q.Response=DisplayReadProtocol.Parse(request[2],frame.AsSpan(),request[2]==0x83?request[3]:(byte)0);break;
                        }
                    }
                }
                catch(OperationCanceledException)
                {q.Response=new(q.InputReports.Count>0?unexpected?DisplayResponseKind.UNKNOWN:DisplayResponseKind.MALFORMED:DisplayResponseKind.TIMEOUT);q.Error=ct.IsCancellationRequested?"Cancelled":"Timeout; no retry";}
                catch(Exception ex){q.Response=new(ex is FormatException?DisplayResponseKind.MALFORMED:DisplayResponseKind.UNKNOWN);q.Error=ex.GetType().Name;}
                Trace?.Invoke("QueryComplete",q);
                if(ct.IsCancellationRequested || q.NativeResult is not {Success:true,BytesWritten:65} || !session.ReaderRunning || i==0 && q.Response.Telemetry is null)break;
            }
        }
        catch(Exception ex){result.RunError=ex.GetType().Name;Trace?.Invoke("RunError",new{result.RunError});}
        finally
        {
            session.Cancel();await session.DisposeAsync();result.TeardownCompleted=true;result.ReaderStopped=!session.ReaderRunning;result.ClosedAt=DateTimeOffset.UtcNow;
            Trace?.Invoke("Closed",new{result.SessionId,result.ReaderStopped,result.TeardownCompleted,result.ClosedAt});
        }
        return result;
    }
}

using AhaKey.Core;
namespace AhaKey.Device;

public sealed class PhysicalFeedbackService(DeviceManager manager)
{
    private readonly PhysicalFeedbackPolicy policy=new();
    private readonly SemaphoreSlim gate=new(1,1);
    private long received,duplicates,operations,successful;
    public long Received=>Interlocked.Read(ref received);
    public long SuppressedDuplicates=>Interlocked.Read(ref duplicates);
    public long PhysicalOperations=>Interlocked.Read(ref operations);
    public long SuccessfulOperations=>Interlocked.Read(ref successful);
    public async Task<bool> HandleAsync(FeedbackInput input,bool enabled,IReadOnlyDictionary<IdeEventState,byte> map,
        IReadOnlySet<byte> accepted,Action<PhysicalCommandEvidence> record,CancellationToken ct=default,Action<byte,Guid>? beforeSend=null,Action<FeedbackDecision>? report=null,Func<bool>? stillEnabled=null)
    {
        Interlocked.Increment(ref received);
        if(!enabled){report?.Invoke(new(FeedbackDisposition.Disabled));return false;}
        // Give an already-arriving neutral event one bounded chance to follow the current effect.
        var wait=map.GetValueOrDefault(input.Event)==0 ? 5000 : 0;
        if(!await gate.WaitAsync(wait,ct)){report?.Invoke(new(FeedbackDisposition.Busy));return false;}
        try
        {
            if(stillEnabled is not null && !stillEnabled()){report?.Invoke(new(FeedbackDisposition.Disabled));return false;}
            if(manager.RealDevice?.Observation is not {IsLive:true,SessionId:{} session,Status:{} status} || session!=input.Session || status.WorkMode!=(int)input.Profile)
            {report?.Invoke(new(FeedbackDisposition.WrongSessionOrProfile));return false;}
            var decision=policy.Decide(input,enabled,map,accepted,DateTimeOffset.UtcNow);
            if(decision.Disposition==FeedbackDisposition.Duplicate)Interlocked.Increment(ref duplicates);
            var code=decision.Effect;if(code is null){report?.Invoke(decision);return false;}
            var sent=await manager.ExecuteFeedbackAsync(ApprovedControlPlan.RuntimeEffect(session,$"Explicit local feedback opt-in: {input.Integration}/{input.Profile}; {input.Event}",code.Value),input.Profile,stillEnabled??(()=>enabled),
                ()=>{beforeSend?.Invoke(code.Value,session);Interlocked.Increment(ref operations);},record,ct);
            if(!sent){report?.Invoke(new(FeedbackDisposition.Busy));return false;}
            Interlocked.Increment(ref successful);report?.Invoke(new(FeedbackDisposition.Accepted,code));
            return true;
        }
        catch{report?.Invoke(new(FeedbackDisposition.Failed));throw;}
        finally{gate.Release();}
    }
}

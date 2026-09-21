namespace AhaKey.Device;

public enum OperationOutcome { Running, Completed, Failed, OutcomeUncertain, Interrupted }
public sealed record DeviceOperationRecord(Guid Id,long Generation,Guid? Session,PhysicalTransportKind? Transport,
    string Operation,bool Persistent,DateTimeOffset StartedAt,DateTimeOffset? EndedAt,
    OperationOutcome Outcome,int ConfirmedSteps,string? LastConfirmedStep,bool BindingChanged,bool SaveConfirmed)
{public string? LastConfirmedFlashBlock {get;init;}};
// The manager's single ownership gate covers both transports, reads, reconnect and writes.
public sealed class DeviceOperationCoordinator
{
    private readonly SemaphoreSlim gate=new(1,1);
    private readonly List<DeviceOperationRecord> journal=[];
    private readonly object sync=new();
    private long generation;
    public Action<DeviceOperationRecord>? Persist {get;set;}
    public DeviceOperationRecord? Current {get;private set;}
    public IReadOnlyList<DeviceOperationRecord> Journal {get{lock(sync)return journal.ToArray();}}
    public async Task<bool> WaitAsync(int milliseconds,CancellationToken ct)
    {
        if(!await gate.WaitAsync(milliseconds,ct))return false;
        lock(sync)Current=new(Guid.NewGuid(),++generation,null,null,"Device operation",false,DateTimeOffset.UtcNow,null,OperationOutcome.Running,0,null,false,false);
        return true;
    }
    public void Describe(string operation,Guid? session,PhysicalTransportKind? transport,bool persistent)
    {lock(sync){Current=Current! with{Operation=operation,Session=session,Transport=transport,Persistent=persistent};Persist?.Invoke(Current);}}
    public void Confirm(string step,bool binding=false,bool save=false)
    {lock(sync){Current=Current! with{ConfirmedSteps=Current.ConfirmedSteps+1,LastConfirmedStep=step,LastConfirmedFlashBlock=step.StartsWith("81 sector",StringComparison.Ordinal)?step:Current.LastConfirmedFlashBlock,BindingChanged=Current.BindingChanged||binding,SaveConfirmed=Current.SaveConfirmed||save};Persist?.Invoke(Current);}}
    public void Fail(bool mayHaveWritten)
    {lock(sync){if(Current is not null){Current=Current with{Outcome=mayHaveWritten?OperationOutcome.OutcomeUncertain:OperationOutcome.Failed};Persist?.Invoke(Current);}}}
    public void Release()
    {
        try{lock(sync){if(Current is {} item){item=item with{EndedAt=DateTimeOffset.UtcNow,Outcome=item.Outcome==OperationOutcome.Running?OperationOutcome.Completed:item.Outcome};journal.Add(item);if(journal.Count>100)journal.RemoveAt(0);Current=null;Persist?.Invoke(item);}}}
        finally{gate.Release();}
    }
    public static DeviceOperationRecord Recover(DeviceOperationRecord record)=>record.Outcome==OperationOutcome.Running
        ?record with{Outcome=record.Persistent?OperationOutcome.OutcomeUncertain:OperationOutcome.Interrupted}:record;
}

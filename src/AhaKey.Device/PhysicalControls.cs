using System.Collections.Immutable;
using AhaKey.Protocol;
namespace AhaKey.Device;

public sealed record PhysicalCommandEvidence(Guid Session,PhysicalTransportKind Transport,ControlCategory Category,string Operation,
    string Approval,DateTimeOffset StartedAt,DateTimeOffset? CompletedAt,DateTimeOffset? ResponseAt,
    string Tx,string? NativeOutput,string? NativeResult,string? Rx,string? Error)
{public double? LatencyMs=>ResponseAt is {} at?(at-StartedAt).TotalMilliseconds:null;public IReadOnlyList<string> NativeInputReports {get;init;}=[];}
public sealed class PhysicalControlException(PhysicalCommandEvidence evidence):IOException("Physical control stopped; inspect command ledger. No automatic retry.")
{public PhysicalCommandEvidence Evidence {get;}=evidence;}

// One approval is bound to one exact command and one session. It cannot be replayed after reconnect.
public sealed class ApprovedControl
{
    public Guid Session {get;}
    public string Approval {get;}
    public LegacyControlCommand Command {get;}
    private int used;
    internal ApprovedControl(Guid session,string approval,LegacyControlCommand command)
    {Session=session;Approval=approval;Command=command;}
    public void Consume(Guid session,ReadOnlySpan<byte> bytes)
    {if(session!=Session || !bytes.SequenceEqual(Command.Frame.AsSpan()) || Interlocked.Exchange(ref used,1)!=0)throw new InvalidOperationException("Approval does not match this one-shot command/session.");}
}
public sealed class ApprovedControlPlan
{
    public Guid Session {get;}
    public string Approval {get;}
    public ImmutableArray<LegacyControlCommand> Commands {get;}
    private int used;
    private ApprovedControlPlan(Guid session,string approval,ImmutableArray<LegacyControlCommand> commands)
    {if(session==Guid.Empty || string.IsNullOrWhiteSpace(approval))throw new ArgumentException("Explicit approval and session required.");Session=session;Approval=approval;Commands=commands;}
    public static ApprovedControlPlan Key(Guid session,string approval,KeyWritePlan plan)
    {
        // Reconstruct and compare the plan; public record construction cannot smuggle another address or operation.
        var full=KeyWritePlan.Create(plan.Profile,plan.Key,plan.Value);
        if(plan.Commands.Length is <2 or >3 || plan.Commands[^1].Opcode!=4 || plan.Commands[..^1].Any(c=>!full.Commands[..^1].Any(f=>f.Frame.SequenceEqual(c.Frame))) || plan.Commands[..^1].Select(c=>c.Operation).Distinct().Count()!=plan.Commands.Length-1)
            throw new ArgumentException("Invalid minimal key plan.");
        return new(session,approval,plan.Commands);
    }
    public static ApprovedControlPlan RuntimeEffect(Guid session,string approval,byte code) => new(session,approval,[LegacyControlCommand.Effect(code)]);
    public static ApprovedControlPlan WorkProfile(Guid session,string approval,AhaKey.Core.HardwareProfileId profile) => new(session,approval,[LegacyControlCommand.WorkProfile(profile)]);
    public static ApprovedControlPlan Brightness(Guid session,string approval,byte value)=>new(session,approval,[LegacyControlCommand.Brightness(value),LegacyControlCommand.SaveKeys()]);
    public static ApprovedControlPlan LightingMap(Guid session,string approval,AhaKey.Core.HardwareProfileId profile,IReadOnlyList<byte> values)=>new(session,approval,[LegacyControlCommand.LightingMap(profile,values),LegacyControlCommand.SaveKeys()]);
    public static ApprovedControlPlan AssistantState(Guid session,string approval,byte state)=>new(session,approval,[LegacyControlCommand.AssistantState(state)]);
    internal static ApprovedControlPlan K1Experiment(Guid session,string approval,bool restore) =>
        new(session,approval,[LegacyControlCommand.K1Experiment(restore),LegacyControlCommand.SaveKeys()]);
    public ImmutableArray<ApprovedControl> Begin(Guid currentSession)
    {if(currentSession!=Session || Interlocked.Exchange(ref used,1)!=0)throw new InvalidOperationException("Plan is stale or was already executed.");return Commands.Select(c=>new ApprovedControl(Session,Approval,c)).ToImmutableArray();}
}
public interface IPhysicalControlTransport
{
    Task<PhysicalCommandEvidence> SendControlAsync(ApprovedControl command,CancellationToken ct);
}

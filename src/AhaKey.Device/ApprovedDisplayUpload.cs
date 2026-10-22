using System.Collections.Immutable;
using AhaKey.Protocol;
namespace AhaKey.Device;

public sealed class ApprovedDisplayReport
{
    private readonly ApprovedDisplayUpload owner;private readonly int sequence;
    public ImmutableArray<byte> Report {get;}
    internal ApprovedDisplayReport(ApprovedDisplayUpload owner,int sequence,ImmutableArray<byte> report)
    {this.owner=owner;this.sequence=sequence;Report=report;}
    public void Consume(Guid session)=>owner.Consume(session,sequence,Report);
}
// Exact bytes, hash, session, order and one-use permits. No arbitrary A1/A2 escape hatch.
public sealed class ApprovedDisplayUpload
{
    private int begun,next;private readonly object sync=new();
    private readonly ImmutableArray<ImmutableArray<byte>> reports;
    public Guid Session {get;}
    public string Approval {get;}
    public StaticDisplayPlan Plan {get;}=null!;
    public Windows32DisplayUploadPlan? Modern {get;}
    public ImmutableArray<DisplayFlashBlock> Blocks=>Modern?.Transfer.Blocks??Plan.Blocks;
    public ImmutableArray<byte> Binding=>Modern?.Transfer.Binding??Plan.Binding;
    public ImmutableArray<byte> Verify=>Modern?.Verify??Plan.Verify;
    public bool MatchesBinding(ReadOnlySpan<byte> frame,bool exact)=>Modern?.MatchesBinding(frame,exact)??Plan.MatchesBinding(frame);
    public ApprovedDisplayUpload(Guid session,string approval,string approvedSha256,Windows32DisplayUploadPlan plan)
    {
        if(session==Guid.Empty||string.IsNullOrWhiteSpace(approval)||approvedSha256!=plan.Sha256)throw new ArgumentException("Exact target/hash/session required.");
        Session=session;Approval=approval;Modern=plan;
        var bytes=ImmutableArray.CreateBuilder<ImmutableArray<byte>>();bytes.Add(StaticDisplayPlan.A1(plan.Verify));
        foreach(var block in plan.Transfer.Blocks){bytes.Add(StaticDisplayPlan.A1(block.Prepare));bytes.AddRange(block.UsbA2Reports());}
        bytes.Add(StaticDisplayPlan.A1(plan.Transfer.Binding));bytes.Add(StaticDisplayPlan.A1(plan.Transfer.Persistence));bytes.Add(StaticDisplayPlan.A1(plan.Verify));reports=bytes.ToImmutable();
    }
    public ApprovedDisplayUpload(Guid session,string approval,string approvedSha256,StaticDisplayPlan plan)
    {
        if(session==Guid.Empty || string.IsNullOrWhiteSpace(approval) || approvedSha256!=plan.Sha256)throw new ArgumentException("Explicit exact-frame/session approval required.");
        Session=session;Approval=approval;Plan=plan;
        var bytes=ImmutableArray.CreateBuilder<ImmutableArray<byte>>();bytes.Add(StaticDisplayPlan.A1(plan.Verify));
        foreach(var block in plan.Blocks){bytes.Add(StaticDisplayPlan.A1(block.Prepare));bytes.AddRange(block.UsbA2Reports());}
        bytes.Add(StaticDisplayPlan.A1(plan.Binding));bytes.Add(StaticDisplayPlan.A1(plan.Save));bytes.Add(StaticDisplayPlan.A1(plan.Verify));reports=bytes.ToImmutable();
    }
    public ImmutableArray<ApprovedDisplayReport> Begin(Guid session)
    {
        if(session!=Session || Interlocked.Exchange(ref begun,1)!=0)throw new InvalidOperationException("Upload permit is stale or consumed.");
        return reports.Select((r,i)=>new ApprovedDisplayReport(this,i,r)).ToImmutableArray();
    }
    internal void Consume(Guid session,int sequence,ImmutableArray<byte> report)
    {lock(sync){if(begun!=1 || session!=Session || sequence!=next || !reports[next].SequenceEqual(report))throw new InvalidOperationException("Display report order/session rejected.");next++;}}
}
public sealed record DisplayTransferEvidence(Guid Session,int Sequence,string Stage,DateTimeOffset StartedAt,
    DateTimeOffset? CompletedAt,string NativeOutput,string? NativeResult,string? Error);
public sealed record DisplayResponseEvidence(Guid Session,string Stage,DateTimeOffset At,string Frame,IReadOnlyList<string> NativeInputReports);
public sealed record StaticDisplayAcceptance(Guid Session,int Profile,int Slot,string FrameSha256,bool ProtocolAccepted,bool MetadataMatches,bool VisuallyObserved)
{
    public bool PromotesCapability=>Session!=Guid.Empty && Profile==2 && Slot==9 && FrameSha256.Length==64 && FrameSha256.All(Uri.IsHexDigit) && ProtocolAccepted && MetadataMatches && VisuallyObserved;
}

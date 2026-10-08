using AhaKey.Protocol;
namespace AhaKey.Device;

public sealed record K1BehaviorEvidence(Guid Session,bool BaselineF18,bool TestWriteAccepted,bool ObservedF19,
    bool RestoreWriteAccepted,bool ObservedF18,bool Failed)
{
    public bool PromotesCapability => Session!=Guid.Empty && BaselineF18 && TestWriteAccepted && ObservedF19 && RestoreWriteAccepted && ObservedF18 && !Failed;
}

// One bounded test and one restore, in the same session. ACK is never behavioral evidence.
public sealed class ReversibleK1Trial(Guid session,string approval)
{
    private bool baseline,testStarted,testAccepted,f19,restoreStarted,restoreAccepted,f18,failed;
    public K1BehaviorEvidence Evidence => new(session,baseline,testAccepted,f19,restoreAccepted,f18,failed);
    public void ObserveBaseline(string value)
    {if(testStarted || baseline || value!="F18")throw new InvalidOperationException("Expected baseline F18 before the test.");baseline=true;}
    public ApprovedControlPlan BeginTest()
    {if(!baseline || testStarted || failed)throw new InvalidOperationException("K1 trial cannot start/retry.");testStarted=true;return ApprovedControlPlan.K1Experiment(session,approval,false);}
    public void TestAccepted()
    {if(!testStarted || restoreStarted || failed)throw new InvalidOperationException();testAccepted=true;}
    public bool ObserveTest(string value)
    {if(!testAccepted || restoreStarted || value!="F19")return false;return f19=true;}
    public ApprovedControlPlan BeginRestore()
    {if(!testStarted || restoreStarted)throw new InvalidOperationException("K1 restore cannot start/retry.");restoreStarted=true;return ApprovedControlPlan.K1Experiment(session,approval+"; restore F18",true);}
    public void RestoreAccepted()
    {if(!restoreStarted)throw new InvalidOperationException();restoreAccepted=true;}
    public bool ObserveRestore(string value)
    {if(!restoreAccepted || value!="F18")return false;return f18=true;}
    public void Fail()=>failed=true;
}

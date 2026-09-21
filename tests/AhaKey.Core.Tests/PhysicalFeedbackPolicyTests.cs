using AhaKey.Core;
namespace AhaKey.Core.Tests;
public class PhysicalFeedbackPolicyTests
{
    [Fact] public void NativeAliasesCannotDoubleFlashAndFastNeutralIsNotBurstSuppressed()
    {
        var policy=new PhysicalFeedbackPolicy();var id=Guid.NewGuid();var now=DateTimeOffset.UtcNow;
        var input=new FeedbackInput(id,HardwareProfileId.Codex,"Codex",IdeEventState.UserPromptSubmit,"legacy");
        var map=new Dictionary<IdeEventState,byte>{{IdeEventState.UserPromptSubmit,1},{IdeEventState.Stop,0}};var accepted=new HashSet<byte>{0,1};
        Assert.Equal(FeedbackDisposition.Disabled,policy.Decide(input,false,map,accepted,now).Disposition);
        Assert.Equal((byte)1,policy.Decide(input,true,map,accepted,now).Effect);
        Assert.Equal(FeedbackDisposition.Duplicate,policy.Decide(input with{NativeEvent="studio"},true,map,accepted,now.AddSeconds(1)).Disposition);
        Assert.Equal((byte)0,policy.Decide(input with{Event=IdeEventState.Stop},true,map,accepted,now.AddMilliseconds(10)).Effect);
    }
    [Fact] public void BoundedDedupDoesNotReplayOrCrossSessions()
    {
        var p=new PhysicalFeedbackPolicy();var e=new FeedbackInput(Guid.NewGuid(),HardwareProfileId.Codex,"Codex",IdeEventState.PreToolUse,"CodexPreToolUse");
        var map=new Dictionary<IdeEventState,byte>{{e.Event,1}};var accepted=new HashSet<byte>{0,1};var now=DateTimeOffset.UtcNow;
        Assert.Null(p.Select(e,false,map,accepted,now));Assert.Equal((byte)1,p.Select(e,true,map,accepted,now));
        Assert.Null(p.Select(e,true,map,accepted,now.AddSeconds(19)));Assert.Equal((byte)1,p.Select(e,true,map,accepted,now.AddSeconds(31)));
        Assert.Equal((byte)1,p.Select(e with{Session=Guid.NewGuid()},true,map,accepted,now.AddSeconds(32)));
    }
    [Fact] public void SourceCodeDoesNotEqualPhysicallyAcceptedEffect()
    {
        var p=new PhysicalFeedbackPolicy();var e=new FeedbackInput(Guid.NewGuid(),HardwareProfileId.Codex,"Codex",IdeEventState.Stop,"CodexStop");
        Assert.Null(p.Select(e,true,new Dictionary<IdeEventState,byte>{{e.Event,16}},new HashSet<byte>{0,1},DateTimeOffset.UtcNow));
    }
}

using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Protocol;
namespace AhaKey.Device.Tests;

public sealed class ReversibleK1Tests
{
    [Fact] public void ExactTestAndRestorePlansAreOneShotAndSessionBound()
    {
        var id=Guid.NewGuid();var trial=new ReversibleK1Trial(id,"Explicit test + restore approval");
        Assert.Throws<InvalidOperationException>(()=>trial.BeginTest());trial.ObserveBaseline("F18");
        var plan=trial.BeginTest();Assert.Equal(new[]{"AABB737302006ECCDD","AABB04CCDD"},plan.Commands.Select(c=>Convert.ToHexString(c.Frame.AsSpan())));
        Assert.Throws<InvalidOperationException>(()=>trial.BeginTest());Assert.Throws<InvalidOperationException>(()=>plan.Begin(Guid.NewGuid()));
        var once=plan.Begin(id);Assert.Throws<InvalidOperationException>(()=>plan.Begin(id));
        once[0].Consume(id,once[0].Command.Frame.AsSpan());Assert.Throws<InvalidOperationException>(()=>once[0].Consume(id,once[0].Command.Frame.AsSpan()));
        var restore=trial.BeginRestore();Assert.Equal(new[]{"AABB737302006DCCDD","AABB04CCDD"},restore.Commands.Select(c=>Convert.ToHexString(c.Frame.AsSpan())));
        Assert.Throws<InvalidOperationException>(()=>trial.BeginRestore());
    }
    [Fact] public void BothObservedBehaviorsAndAcceptedWritesAreRequired()
    {
        var trial=new ReversibleK1Trial(Guid.NewGuid(),"approved");trial.ObserveBaseline("F18");trial.BeginTest();
        Assert.False(trial.ObserveTest("F19"));trial.TestAccepted();Assert.False(trial.ObserveTest("F18"));
        Assert.True(trial.ObserveTest("F19"));Assert.False(trial.Evidence.PromotesCapability);
        trial.BeginRestore();Assert.False(trial.ObserveRestore("F18"));trial.RestoreAccepted();
        Assert.False(trial.ObserveRestore("F19"));Assert.True(trial.ObserveRestore("F18"));Assert.True(trial.Evidence.PromotesCapability);
        trial.Fail();Assert.False(trial.Evidence.PromotesCapability);
    }
    [Fact] public void FailedOrMissingRestorationNeverPromotesAndCannotRetry()
    {
        var trial=new ReversibleK1Trial(Guid.NewGuid(),"approved");trial.ObserveBaseline("F18");trial.BeginTest();trial.TestAccepted();trial.ObserveTest("F19");
        trial.BeginRestore();trial.Fail();Assert.False(trial.Evidence.PromotesCapability);
        Assert.Throws<InvalidOperationException>(()=>trial.BeginRestore());Assert.Throws<InvalidOperationException>(()=>trial.BeginTest());
    }
    [Fact] public void OrdinaryK1WriteStillRejectedBeforeAcceptance()
    {
        Assert.True(ShortcutGesture.TryParse("F19",out var gesture));
        Assert.Throws<ArgumentOutOfRangeException>(()=>LegacyControlCommand.Shortcut(HardwareProfileId.Codex,PhysicalKey.K1,gesture!));
    }
}

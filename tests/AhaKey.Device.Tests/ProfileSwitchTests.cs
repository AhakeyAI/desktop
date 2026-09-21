using AhaKey.Core;
using AhaKey.Protocol;
namespace AhaKey.Device.Tests;
public class ProfileSwitchTests
{
    [Fact] public void RuntimePlansContainOneSelectorAndNeverSaveOrKeyWrites()
    {
        var id=Guid.NewGuid();
        foreach(var (profile,hex) in new[]{(HardwareProfileId.Cursor,"AABB9201CCDD"),(HardwareProfileId.Codex,"AABB9202CCDD")})
        {
            var plan=ApprovedControlPlan.WorkProfile(id,"explicit reversible test",profile);
            Assert.Single(plan.Commands);Assert.Equal(hex,Convert.ToHexString(plan.Commands[0].Frame.AsSpan()));
            Assert.Equal(ControlCategory.ProfileRuntime,plan.Commands[0].Category);
            var command=plan.Begin(id).Single();command.Consume(id,command.Command.Frame.AsSpan());
            Assert.Throws<InvalidOperationException>(()=>plan.Begin(id));
        }
        Assert.Throws<ArgumentOutOfRangeException>(()=>LegacyControlCommand.WorkProfile((HardwareProfileId)4));
        Assert.False(AhaKeyProtocol.IsAllowedQuery(Convert.FromHexString("AABB9201CCDD")));
    }
    [Theory][InlineData(false,true)][InlineData(true,false)][InlineData(false,false)]
    public void AckWithoutBothObservedModesDoesNotPromote(bool mode1,bool mode2)
    {Assert.False(new ProfileSwitchAcceptance(Guid.NewGuid(),true,true,mode1,true,mode2).Accepted);}
    [Fact] public void ExactBothObservedModesAndAcksPromote()
    {
        var p=new ProfileSwitchAcceptance(Guid.NewGuid(),true,true,true,true,true);Assert.True(p.Accepted);
        Assert.False((p with{RestoreAck=false}).Accepted);Assert.False((p with{Baseline2=false}).Accepted);
    }
    [Fact] public void Usb92AcknowledgementRequiresExplicitControlParser()
    {
        byte[] ack=Convert.FromHexString("AABB9200CCDD");
        Assert.Empty(new UsbFrameAccumulator().Feed(ack));
        Assert.Single(new UsbFrameAccumulator(includeControlAcks:true).Feed(ack));
        Assert.True(LegacyControlCommand.WorkProfile(HardwareProfileId.Cursor).AcceptsResponse(ack));
    }
}

using AhaKey.Core;
using AhaKey.Protocol;
namespace AhaKey.Protocol.Tests;
public sealed class Phase8ProtocolTests
{
    [Fact] public void EveryFixedAllocationContainsItsWholeEraseAndPixelRange()
    {
        int next=0;
        foreach(var profile in Enum.GetValues<HardwareProfileId>())foreach(var state in Enum.GetValues<DisplayState>())
        {
            var allocation=Windows32DisplayGeometry.Target(profile,state);Assert.Equal(next,allocation.StartSlot);
            var plan=Windows32DisplayUploadPlan.Create(profile,state,Enumerable.Range(0,allocation.Capacity).Select(_=>new byte[25600]).ToArray(),200);
            Assert.All(plan.Transfer.Blocks,b=>{Assert.True(allocation.Contains(b.Address,b.Length));Assert.True(allocation.Contains(b.Sector*4096,4096));});
            Assert.Equal(allocation.Capacity,plan.FrameHashes.Length);Assert.Throws<ArgumentOutOfRangeException>(()=>Windows32DisplayUploadPlan.Create(profile,state,Enumerable.Range(0,allocation.Capacity+1).Select(_=>new byte[25600]).ToArray(),200));next+=allocation.Capacity;
        }
        Assert.Equal(176,next);Assert.Equal(88,Windows32DisplayGeometry.Target(HardwareProfileId.Codex,DisplayState.Default).StartSlot);
    }
    [Fact] public void MetadataVerificationRequiresExactNewTarget()
    {
        var plan=Windows32DisplayUploadPlan.Create(HardwareProfileId.Codex,DisplayState.Default,[new byte[25600]],100);
        Assert.True(plan.MatchesBinding(Convert.FromHexString("AABB8300025800010064002401CCDD"),true));
        Assert.False(plan.MatchesBinding(Convert.FromHexString("AABB8300020900010064002401CCDD"),true));
        Assert.True(plan.MatchesBinding(Convert.FromHexString("AABB8300020900010064002401CCDD"),false));
    }
    [Fact] public void ResourceReadSurvivesEveryFragmentBoundary()
    {
        var frame=Convert.FromHexString("AABB9D0000016400087302E02800000000CCDD");
        for(int i=1;i<frame.Length;i++){var parser=new UsbFrameAccumulator(includeConfigReads:true);Assert.Empty(parser.Feed(frame.AsSpan(0,i)));Assert.Equal(frame,parser.Feed(frame.AsSpan(i)).Single().ToArray());}
    }
    [Fact] public void KeyReadDoesNotGuessMacrosOrLabels()
    {
        byte[] resource=new byte[100];resource[0]=0x73;resource[1]=2;resource[2]=0xE0;resource[3]=0x28;
        Assert.Equal("Ctrl+Enter",KeyResource.Shortcut(resource)!.Canonical);resource[0]=0x74;Assert.Null(KeyResource.Shortcut(resource));
        resource[0]=0x73;resource[1]=3;resource[4]=0x29;Assert.Null(KeyResource.Shortcut(resource));
    }
    [Fact] public void PersistentLightingAndRuntimeCommandsRemainDistinct()
    {
        Assert.Equal("AABB8550CCDD",Convert.ToHexString(LegacyControlCommand.Brightness(80).Frame.AsSpan()));
        Assert.Throws<ArgumentOutOfRangeException>(()=>LegacyControlCommand.Brightness(0));
        Assert.Equal(0x84,LegacyControlCommand.LightingMap(HardwareProfileId.Codex,new byte[9]).Opcode);
        Assert.Throws<ArgumentException>(()=>LegacyControlCommand.LightingMap(HardwareProfileId.Codex,Enumerable.Repeat((byte)17,9).ToArray()));
        Assert.Equal(0x90,LegacyControlCommand.AssistantState(8).Opcode);
    }
}

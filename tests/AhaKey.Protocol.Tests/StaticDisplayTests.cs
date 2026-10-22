using AhaKey.Protocol;
namespace AhaKey.Protocol.Tests;
public class StaticDisplayTests
{
    [Fact] public void OneFrameBoundAssetUsesSlot9AndSevenExactEraseSectors()
    {
        var plan=StaticDisplayPlan.Create(StaticDisplayPlan.ExpectedBinding,[new byte[25600]]);
        Assert.Equal(0x03F000,plan.StartAddress);Assert.Equal(0x0453FF,plan.PixelEnd);Assert.Equal(0x045FFF,plan.EraseEnd);
        Assert.Equal(7,plan.Blocks.Length);Assert.Equal(Enumerable.Range(63,7),plan.Blocks.Select(b=>b.Sector));
        Assert.Equal(new[]{4096,4096,4096,4096,4096,4096,1024},plan.Blocks.Select(b=>b.Length));
        Assert.Equal("AABB8000001000F00300CCDD",Convert.ToHexString(plan.Blocks[0].Prepare.AsSpan()));
        Assert.Equal("AABB8000000400500400CCDD",Convert.ToHexString(plan.Blocks[^1].Prepare.AsSpan()));
        Assert.Equal(425,plan.A2ReportCount);Assert.Equal("AABB8202090001006400CCDD",Convert.ToHexString(plan.Binding.AsSpan()));
        Assert.Equal("AABB04CCDD",Convert.ToHexString(plan.Save.AsSpan()));
        Assert.True(plan.MatchesBinding(Convert.FromHexString("AABB8300020900010064002401CCDD")));
        Assert.False(plan.MatchesBinding(Convert.FromHexString("AABB8300020800010064002401CCDD")));
    }
    [Fact] public void ChangedRangeMetadataAndAnimationAreRejected()
    {
        var b=StaticDisplayPlan.ExpectedBinding;var f=new byte[25600];
        foreach(var other in new[]{b with{Profile=3},b with{Start=292},b with{Count=0},b with{TotalFrameSlots=8},b with{State=1},b with{IntervalMs=0}})
            Assert.Throws<ArgumentException>(()=>StaticDisplayPlan.Create(other,[f]));
        Assert.Throws<ArgumentException>(()=>StaticDisplayPlan.Create(b,[f,f]));Assert.Throws<ArgumentException>(()=>StaticDisplayPlan.Create(b,[new byte[25601]]));
    }
    [Fact] public void A2ReassemblesExactPythonLogicalBlocksWithJavaUsbBatchBoundaries()
    {
        var bytes=Enumerable.Range(0,25600).Select(i=>(byte)(i*37)).ToArray();var plan=StaticDisplayPlan.Create(StaticDisplayPlan.ExpectedBinding,[bytes]);
        Assert.Equal(bytes,plan.Blocks.SelectMany(block=>block.UsbA2Reports().SelectMany(report=>report.Skip(3).Take(report[2]))));
        Assert.All(plan.Blocks,b=>Assert.All(b.UsbA2Reports(),r=>{Assert.Equal(65,r.Length);Assert.Equal(0,r[0]);Assert.Equal(0xA2,r[1]);Assert.InRange(r[2],1,62);Assert.All(r.Skip(3+r[2]),v=>Assert.Equal(0,v));}));
        Assert.Equal(68,plan.Blocks[0].UsbA2Reports().Count());Assert.Equal(17,plan.Blocks[^1].UsbA2Reports().Count());
    }
}

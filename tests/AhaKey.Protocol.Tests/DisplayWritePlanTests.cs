using AhaKey.Core;
using AhaKey.Protocol;
namespace AhaKey.Protocol.Tests;
public class DisplayWritePlanTests
{
    [Fact] public void Rgb565UsesBigEndianTruncatedComponents()
    {
        var rgb=new byte[160*80*3];byte[] pixels=[255,0,0,0,255,0,0,0,255,255,255,255,127,63,31];pixels.CopyTo(rgb,0);
        Assert.Equal("F80007E0001FFFFF79E3",Convert.ToHexString(DisplayPixelEncoder.Rgb565(rgb).AsSpan(0,10)));
        Assert.Throws<ArgumentException>(()=>DisplayPixelEncoder.Rgb565([1,2,3]));
    }
    [Fact] public void UniformTimingPreservesDurationAndBoundedIndices()
    {
        var p=DisplayTiming.Create([0,100,200,300],2);Assert.Equal(350,p.IntervalMs);Assert.Equal(700,p.SourceDurationMs);Assert.Equal(new[]{1,3},p.SourceIndices);
        Assert.Equal(65535,DisplayTiming.Create([1000000],1).IntervalMs);
        Assert.Throws<ArgumentOutOfRangeException>(()=>DisplayTiming.Create([],8));
    }
    [Fact] public void PlanMapsBlocksReportsAndNeverAuthorizesPhysicalUpload()
    {
        var p=DisplayWritePlan.Create(HardwareProfileId.Codex,DisplayState.Default,[new byte[25600]],100);
        Assert.Equal(88,p.StartSlot);Assert.Equal(7,p.Blocks.Length);Assert.Equal(88*28672,p.Blocks[0].Address);
        Assert.Equal(1024,p.Blocks[^1].Length);Assert.Equal(25600,p.TotalBytes);
        Assert.Equal("AABB8202580001006400CCDD",Convert.ToHexString(p.Binding.AsSpan()));
        var b=p.Blocks[0];Assert.Equal("AABB8000001000802600CCDD",Convert.ToHexString(b.Prepare.AsSpan()));
        var reports=b.UsbA2Reports().ToArray();Assert.Equal(68,reports.Length);Assert.All(reports,r=>Assert.Equal(65,r.Length));Assert.Equal(32,reports[16][2]);
        Assert.Equal(b.Data.ToArray(),reports.SelectMany(r=>r.Skip(3).Take(r[2])).ToArray());
        Assert.Equal(4,b.JavaBatches().Count());Assert.False(p.PhysicalUploadAllowed);Assert.False(p.RollbackAvailable);
        Assert.Throws<ArgumentOutOfRangeException>(()=>DisplayWritePlan.Create(HardwareProfileId.Codex,DisplayState.Default,Enumerable.Repeat(new byte[25600],9).ToArray(),100));
        Assert.Throws<ArgumentOutOfRangeException>(()=>DisplayWritePlan.Create((HardwareProfileId)4,DisplayState.Default,[new byte[25600]],100));
    }
    [Fact] public void BrightnessHasRestoreButNoPersistenceOrPhysicalApproval()
    {
        var p=BrightnessRestorePlan.Create(35,40);Assert.False(p.PhysicalAllowed);
        Assert.Equal(new[]{"AABB8528CCDD","AABB8523CCDD"},p.Commands.Select(c=>Convert.ToHexString(c.Frame.AsSpan())));
        Assert.Throws<ArgumentOutOfRangeException>(()=>BrightnessRestorePlan.Create(0,40));
    }
    [Theory][InlineData(DisplayState.Working,1,8)][InlineData(DisplayState.WaitingError,2,20)][InlineData(DisplayState.Completed,3,32)]
    public void AiBindingUsesJavaOneBasedAssetIds(DisplayState state,byte id,int slot)
    {var plan=DisplayWritePlan.Create(HardwareProfileId.Claude,state,[new byte[25600]],100);Assert.Equal(0x93,plan.Binding[2]);Assert.Equal(id,plan.Binding[4]);Assert.Equal(slot,plan.StartSlot);}
}

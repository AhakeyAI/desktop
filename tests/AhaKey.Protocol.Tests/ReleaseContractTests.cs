using AhaKey.Protocol;
namespace AhaKey.Protocol.Tests;
public sealed class ReleaseContractTests
{
    [Fact]public void ProfileSequenceRolloverDuplicatesAndPreviousSession()
    {
        var id=Guid.NewGuid();var tracker=new ModeSyncTracker();tracker.Reset(id);
        byte[] Frame(byte mode,byte source,byte seq)=>[0xAA,0xBB,0x9B,0,mode,source,seq,0xCC,0xDD];
        Assert.True(tracker.Accept(id,Frame(2,0,254),out _));Assert.True(tracker.Accept(id,Frame(1,1,255),out _));
        Assert.True(tracker.Accept(id,Frame(2,2,0),out _));Assert.False(tracker.Accept(id,Frame(1,1,255),out _));
        Assert.False(tracker.Accept(id,Frame(1,1,0),out _));Assert.False(tracker.Accept(id,Frame(4,1,1),out _));
        Assert.False(tracker.Accept(id,Frame(1,3,1),out _));var next=Guid.NewGuid();tracker.Reset(next);
        Assert.False(tracker.Accept(id,Frame(1,1,1),out _));Assert.True(tracker.Accept(next,Frame(1,0,0),out _));
    }
    [Fact]public void GeometryRequiresEveryFieldIncludingAllocationCapacities()
    {
        var layout=new DisplayLayout(4,4,12,25600,7,160,80,0x8516,8388608,292,[8,12,12,12]);
        Assert.True(DisplayGeometryContract.Matches(layout));
        foreach(var wrong in new[]{layout with{Profiles=3},layout with{AssetsPerProfile=3},layout with{Width=159},layout with{BytesPerFrame=25000},layout with{SectorsPerFrame=6},layout with{PhysicalFlashBytes=2097152},layout with{PhysicalFrameSlots=291},layout with{AssetCapacities=[8,8,12,12]},layout with{PhysicalFlashBytes=null}})
            Assert.False(DisplayGeometryContract.Matches(wrong));
    }
    [Fact]public void HeartbeatIsSevenBytesAndStatusContainsCountdownNotMask()
    {
        var heartbeat=LegacyControlCommand.TaskHeartbeat();Assert.True(heartbeat.AcceptsResponse([0xAA,0xBB,0x9A,0,15,0xCC,0xDD]));
        Assert.False(heartbeat.AcceptsResponse([0xAA,0xBB,0x9A,0,0xCC,0xDD]));
        byte[] status=[0xAA,0xBB,0x9A,0,1,30,0,1,1,1,2,1,2,3,1,3,4,1,0xCC,0xDD];
        Assert.Equal(30,TaskProtocol.ParseStatus(status).HeartbeatSeconds);Assert.True(LegacyControlCommand.TaskStatus().AcceptsResponse(status));
        status[8]=2;Assert.False(LegacyControlCommand.TaskStatus().AcceptsResponse(status));
    }
    [Theory][InlineData(0)][InlineData(5)][InlineData(10)][InlineData(15)][InlineData(30)]
    public void SleepUsesLittleEndianAndExactReadback(int minutes)
    {var command=LegacyControlCommand.Standby((ushort)minutes);Assert.Equal(new byte[]{0xAA,0xBB,0x95,(byte)minutes,0,0xCC,0xDD},command.Frame);Assert.Equal(minutes,TaskProtocol.ParseStandby([0xAA,0xBB,0x95,0,(byte)minutes,0,0xCC,0xDD]));}
    [Fact]public void EveryAllocationAcceptsItsFinalFrameAndRejectsOverflow()
    {
        foreach(var profile in Enum.GetValues<AhaKey.Core.HardwareProfileId>())foreach(var state in Enum.GetValues<AhaKey.Core.DisplayState>())
        {
            int capacity=AhaKey.Core.Windows32DisplayGeometry.Capacity(state);
            var frames=Enumerable.Range(0,capacity).Select(_=>new byte[25600]).ToArray();var plan=Windows32DisplayUploadPlan.Create(profile,state,frames,100);
            Assert.All(plan.Transfer.Blocks,b=>Assert.True(plan.Allocation.Contains(b.Sector*4096,4096)));
            Assert.Throws<ArgumentOutOfRangeException>(()=>Windows32DisplayUploadPlan.Create(profile,state,frames.Append(new byte[25600]).ToArray(),100));
        }
    }
}

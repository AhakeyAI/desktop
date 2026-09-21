using AhaKey.Protocol;
namespace AhaKey.Protocol.Tests;
public sealed class DisplayReadTests
{
    [Fact] public void CompletionScopeQueriesEachDefaultOnceAndRejectsOtherReadsAndWrites()
    {
        var guard=new DisplayCharacterizationGuard(defaultBindings:true);
        Assert.Equal(6,guard.QueryCount);
        string[] expected=["AABB00CCDD","AABB8300CCDD","AABB8301CCDD","AABB8302CCDD","AABB8303CCDD","AABB00CCDD"];
        for(int i=0;i<6;i++)
        {
            Assert.Equal(expected[i],Convert.ToHexString(guard.Request(i).AsSpan()));
            guard.Consume(guard.Report(i).AsSpan());
            if(i<5)Assert.Throws<InvalidOperationException>(()=>guard.Consume(guard.Report(i).AsSpan()));
        }
        Assert.Throws<InvalidOperationException>(()=>guard.Consume(guard.Report(0).AsSpan()));
        for(int c=0;c<256;c++)
        {var report=guard.Report(1).ToArray();report[5]=(byte)c;if(c!=0x83)Assert.False(guard.IsApprovedReport(report));}
        for(byte profile=0;profile<4;profile++)
        {
            var frame=Frame(0x83,profile,0,0,8,0,100,0,0x24,1);
            Assert.Equal(profile,DisplayReadProtocol.Parse(0x83,frame,profile).Binding!.Profile);
            Assert.Null(DisplayReadProtocol.Parse(0x83,frame,(byte)((profile+1)%4)).Binding);
        }
    }
    private static byte[] Frame(byte cmd,params byte[] payload)=>new byte[]{0xAA,0xBB,cmd,0}.Concat(payload).Concat(new byte[]{0xCC,0xDD}).ToArray();
    private static readonly byte[] Layout=[4,4,12,0,100,7,160,80,0x16,0x85,0,0,0x80,0,0x24,1,8,12,12,12];
    [Theory][InlineData(0,"AABB00CCDD")][InlineData(1,"AABB9CCCDD")][InlineData(2,"AABB8300CCDD")][InlineData(3,"AABB940001CCDD")][InlineData(4,"AABB00CCDD")]
    public void ExactRequestsAndNativeReports(int index,string expected)
    {Assert.Equal(expected,Convert.ToHexString(DisplayReadProtocol.Request(index).AsSpan()));var r=DisplayReadProtocol.Report(index);Assert.Equal(65,r.Length);Assert.Equal(0,r[0]);Assert.Equal(0xA1,r[1]);Assert.Equal(expected.Length/2,r[2]);Assert.True(DisplayReadProtocol.IsApprovedReport(r.AsSpan()));if(index is 1 or 2 or 3)Assert.False(UsbReportCodec.IsAllowedReport(r.AsSpan()));}
    [Fact] public void PopulatedLayoutSeparatesAllFieldsAndComparisons()
    {var r=DisplayReadProtocol.Parse(0x9C,Frame(0x9C,Layout));Assert.Equal(DisplayResponseKind.SUPPORTED_POPULATED,r.Classification);var l=r.Layout!;Assert.Equal(25600,l.BytesPerFrame);Assert.Equal(7,l.SectorsPerFrame);Assert.Equal((ushort)0x8516,l.FlashId);Assert.Equal(8388608u,l.PhysicalFlashBytes);Assert.Equal((ushort)292,l.PhysicalFrameSlots);Assert.Equal(new byte[]{8,12,12,12},l.AssetCapacities!.Value);Assert.Equal(EvidenceComparison.MATCH,l.CapacityComparison);Assert.Equal(EvidenceComparison.MATCH,l.DimensionsComparison);}
    [Theory][InlineData(8)][InlineData(10)][InlineData(14)][InlineData(16)]
    public void CompleteOptionalGroupsRemainOptional(int n)
    {var l=DisplayReadProtocol.Parse(0x9C,Frame(0x9C,Layout[..n])).Layout!;Assert.Null(l.AssetCapacities);Assert.Equal(n>=10,l.FlashId.HasValue);Assert.Equal(n>=14,l.PhysicalFlashBytes.HasValue);Assert.Equal(n>=16,l.PhysicalFrameSlots.HasValue);if(n<14)Assert.Equal(EvidenceComparison.NOT_REPORTED,l.CapacityComparison);}
    [Theory][InlineData(1)][InlineData(7)][InlineData(9)][InlineData(11)][InlineData(13)][InlineData(15)][InlineData(17)][InlineData(19)]
    public void PartialLayoutsAreMalformed(int n)=>Assert.Equal(DisplayResponseKind.MALFORMED,DisplayReadProtocol.Parse(0x9C,Frame(0x9C,Layout[..n])).Classification);
    [Theory][InlineData(0x9C)][InlineData(0x83)][InlineData(0x94)]
    public void EmptyAckNeverDemonstratesSupport(int cmd)
    {var r=DisplayReadProtocol.Parse((byte)cmd,Frame((byte)cmd));Assert.Equal(DisplayResponseKind.EMPTY_SUCCESS_ACK,r.Classification);Assert.Null(r.Layout);Assert.Null(r.Binding);}
    [Fact] public void ReportedCapacityAndDimensionsMismatchNeverUseBoardFallback()
    {var p=Layout.ToArray();p[12]=0x20;p[6]=128;p[7]=64;var l=DisplayReadProtocol.Parse(0x9C,Frame(0x9C,p)).Layout!;Assert.Equal(2097152u,l.PhysicalFlashBytes);Assert.Equal(EvidenceComparison.MISMATCH,l.CapacityComparison);Assert.Equal(EvidenceComparison.MISMATCH,l.DimensionsComparison);}
    [Theory][InlineData(0x83,"0008000C0053002401")][InlineData(0x94,"000108000C0053002401")]
    public void PopulatedBindingsRetainOnlyReturnedFields(int cmd,string p)
    {var r=DisplayReadProtocol.Parse((byte)cmd,Frame((byte)cmd,Convert.FromHexString(p)));Assert.Equal(DisplayResponseKind.SUPPORTED_POPULATED,r.Classification);Assert.Equal(8,r.Binding!.Start);Assert.Equal(12,r.Binding.Count);Assert.Equal(83,r.Binding.IntervalMs);Assert.Equal(292,r.Binding.TotalFrameSlots);Assert.Equal(cmd==0x94,r.Binding.State.HasValue);}
    [Fact] public void UnknownAndExplicitRejectionAreDistinct()
    {Assert.Equal(DisplayResponseKind.UNKNOWN,DisplayReadProtocol.Parse(0x9C,Frame(0x83)).Classification);Assert.Equal(DisplayResponseKind.EXPLICIT_UNSUPPORTED,DisplayReadProtocol.Parse(0x9C,Convert.FromHexString("AABB9C03CCDD")).Classification);Assert.Equal(DisplayResponseKind.UNKNOWN,DisplayReadProtocol.Parse(0x9C,Convert.FromHexString("AABB9C02CCDD")).Classification);Assert.Equal(DisplayResponseKind.UNKNOWN,DisplayReadProtocol.Parse(0x83,Frame(0x83,1,0,0,0,0,0,0,0,0)).Classification);}
    [Fact] public void NoA2NoSettersAndOneShotExactSequence()
    {var guard=new DisplayCharacterizationGuard();for(int command=0;command<256;command++){var r=DisplayReadProtocol.Report(1).ToArray();r[5]=(byte)command;if(command is not (0 or 0x9C))Assert.False(DisplayReadProtocol.IsApprovedReport(r));}var a2=DisplayReadProtocol.Report(0).ToArray();a2[1]=0xA2;Assert.False(DisplayReadProtocol.IsApprovedReport(a2));Assert.Throws<InvalidOperationException>(()=>guard.Consume(DisplayReadProtocol.Report(1).AsSpan()));for(int i=0;i<5;i++)guard.Consume(DisplayReadProtocol.Report(i).AsSpan());Assert.Equal(5,guard.Attempts);Assert.Throws<InvalidOperationException>(()=>guard.Consume(DisplayReadProtocol.Report(0).AsSpan()));}
    [Fact] public void DisplayFramesCanSplitAndContainTrailerBytesInPayload()
    {var p=Layout.ToArray();p[8]=0xCC;p[9]=0xDD;var f=Frame(0x9C,p);var a=new UsbFrameAccumulator(true);Assert.Empty(a.Feed(f.AsSpan(0,7)));Assert.Equal(f,a.Feed(f.AsSpan(7)).Single());Assert.Empty(new UsbFrameAccumulator().Feed(f));}
}

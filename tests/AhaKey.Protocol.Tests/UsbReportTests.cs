using System.Collections.Immutable;
using AhaKey.Protocol;
namespace AhaKey.Protocol.Tests;
public sealed class UsbReportTests
{
    private static readonly byte[] Status=Convert.FromHexString("AABB004B32010002000023CCDD");
    private static readonly byte[] Ack=Convert.FromHexString("AABB9F00CCDD");
    [Theory][InlineData(ReadOnlyQuery.PhysicalStatus,0)][InlineData(ReadOnlyQuery.Capabilities,159)]
    public void QueriesUseOnlyA1AndZeroReportId(ReadOnlyQuery command,int code)
    {var report=UsbReportCodec.EncodeQuery(command);Assert.Equal(65,report.Length);Assert.Equal(new byte[]{0,0xA1,5,0xAA,0xBB,(byte)code,0xCC,0xDD},report.Take(8));Assert.All(report.Skip(8),b=>Assert.Equal(0,b));Assert.True(UsbReportCodec.IsAllowedReport(report.AsSpan()));}
    [Fact]public void EveryOtherCommandAndA2AreRejected()
    {for(int i=0;i<256;i++){if(i is 0 or 159)continue;Assert.Throws<ArgumentOutOfRangeException>(()=>UsbReportCodec.EncodeQuery((ReadOnlyQuery)i));}var bytes=UsbReportCodec.EncodeQuery(0).ToArray();bytes[1]=0xA2;Assert.False(UsbReportCodec.IsAllowedReport(bytes));}
    [Fact]public void WrongNativeLengthOrReportIdOrPaddingIsRejected()
    {var r=UsbReportCodec.EncodeQuery(0).ToArray();Assert.False(UsbReportCodec.IsAllowedReport(r[1..]));r[0]=1;Assert.False(UsbReportCodec.IsAllowedReport(r));r[0]=0;r[64]=1;Assert.False(UsbReportCodec.IsAllowedReport(r));}
    [Fact]public void CompletePaddedReportPreserves13ByteStatus()
    {var r=new byte[65];Status.CopyTo(r,1);var f=new UsbFrameAccumulator().FeedReport(r);Assert.Equal(Status,Assert.Single(f));Assert.Equal(75,AhaKeyProtocol.DecodeStatus(f[0].AsSpan()).Battery);}
    [Theory][InlineData(1)][InlineData(2)][InlineData(5)][InlineData(10)][InlineData(12)]
    public void FrameCanSpanReads(int split)
    {var a=new UsbFrameAccumulator();Assert.Empty(a.Feed(Status.AsSpan(0,split)));Assert.Equal(Status,Assert.Single(a.Feed(Status.AsSpan(split))));}
    [Fact]public void SplitPrefixWithReportIdAndShortAck()
    {var a=new UsbFrameAccumulator();Assert.Empty(a.FeedReport([0,0xAA]));Assert.Equal(Ack,Assert.Single(a.FeedReport([0,0xBB,0x9F,0,0xCC,0xDD])));}
    [Fact]public void MultipleFramesAndZeroPadding()
    {var a=new UsbFrameAccumulator();var frames=a.Feed(Status.Concat(new byte[8]).Concat(Ack).Concat(new byte[9]).ToArray());Assert.Equal(2,frames.Count);Assert.Equal(Ack,frames[1]);Assert.Equal(0,a.BufferedBytes);}
    [Fact]public void EmbeddedTrailerDoesNotSplitStatus()
    {var bytes=(byte[])Status.Clone();bytes[7]=0xCC;bytes[8]=0xDD;Assert.Equal(bytes,Assert.Single(new UsbFrameAccumulator().Feed(bytes)));}
    [Fact]public void EmbeddedTrailerDoesNotSplitNewCapabilities()
    {var bytes=Convert.FromHexString("AABB9F000302010401CCDD00000801CCDD");Assert.Equal(bytes,Assert.Single(new UsbFrameAccumulator().Feed(bytes)));}
    [Fact]public void ShortStatusAckIsAFrameButNotTelemetry()
    {var f=Assert.Single(new UsbFrameAccumulator().Feed(Convert.FromHexString("AABB0001CCDD")));Assert.Throws<FormatException>(()=>AhaKeyProtocol.DecodeStatus(f.AsSpan()));}
    [Fact]public void LegacyCapsHasNoSynthesizedFields()
    {var f=Assert.Single(new UsbFrameAccumulator().Feed(Ack));var c=AhaKeyProtocol.DecodeCapabilities(f.AsSpan());Assert.Null(c.ProtocolMajor);Assert.Null(c.Model);Assert.Null(c.Bits);}
    [Fact]public void InputIsBoundedAndWrongReportIdRejected()
    {var a=new UsbFrameAccumulator();Assert.Throws<FormatException>(()=>a.Feed(new byte[257]));Assert.Equal(0,a.BufferedBytes);Assert.Throws<FormatException>(()=>a.FeedReport([1,0xAA]));}
}

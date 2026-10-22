using AhaKey.Protocol;
namespace AhaKey.Protocol.Tests;
public class PhysicalReadTests
{
    [Theory] [InlineData(12)] [InlineData(13)] [InlineData(14)]
    public void StatusVariantsNeverReadTrailerAsBrightness(int size)
    {
        byte[] f=new byte[size];byte[] head=[0xAA,0xBB,0,99,0xDA,1,4,2,0,1,75,7];Array.Copy(head,f,size-2);f[^2]=0xCC;f[^1]=0xDD;
        var s=AhaKeyProtocol.DecodeStatus(f);Assert.Equal(99,s.Battery);Assert.Equal(-38,s.FirmwareSignal);Assert.Equal(size>=13?(byte?)75:null,s.Brightness);Assert.Equal(size>=14?(byte?)7:null,s.ReadinessFlags);
    }
    [Theory] [InlineData(15)] [InlineData(16)] [InlineData(17)]
    public void CapabilityVariantsPreserveAbsentFields(int size)
    {
        byte[] f=new byte[size];byte[] head=[0xAA,0xBB,0x9F,0,3,2,1,4,2,0xFF,7,0,0,8,1];Array.Copy(head,f,size-2);f[^2]=0xCC;f[^1]=0xDD;
        var c=AhaKeyProtocol.DecodeCapabilities(f);Assert.Equal(0x7FFu,c.Bits);Assert.Equal(size>=16?(byte?)8:null,c.FirmwarePatch);Assert.Equal(size>=17?(byte?)1:null,c.Model);Assert.Equal(size==17,c.SupportedContract);
    }
    [Fact] public void UnknownContractAndMalformedPacketsStayUnsupported()
    {Assert.False(new PhysicalCapabilities(4,0,1,4,1,0x7FF,8,1).SupportedContract);Assert.Throws<FormatException>(()=>AhaKeyProtocol.DecodeStatus([0xAA,0xBB,0,0xCC,0xDD]));Assert.Throws<FormatException>(()=>AhaKeyProtocol.DecodeCapabilities([0xAA,0xBB,0x9F,1,3,2,1,4,1,0xFF,7,0,0,8,1,0xCC,0xDD]));}
    [Fact] public void ObservedStatusOnlyAcknowledgementHasNoFabricatedCapabilities()
    {var c=AhaKeyProtocol.DecodeCapabilities([0xAA,0xBB,0x9F,0,0xCC,0xDD]);Assert.Null(c.ProtocolMajor);Assert.Null(c.FirmwareMajor);Assert.Null(c.Bits);Assert.Null(c.Model);Assert.False(c.SupportedContract);}
    [Fact] public void AllowlistRequiresExactPayloadFreeQuery()
    {Assert.True(AhaKeyProtocol.IsAllowedQuery([0xAA,0xBB,0,0xCC,0xDD]));Assert.False(AhaKeyProtocol.IsAllowedQuery([0xAA,0xBB,0,0,0xCC,0xDD]));Assert.False(AhaKeyProtocol.IsAllowedQuery([0xAA,0xBB,4,0xCC,0xDD]));}
}

using System.Collections.Immutable;
using AhaKey.Core;
namespace AhaKey.Protocol;
public enum ReadOnlyQuery : byte { PhysicalStatus=0x00, Capabilities=0x9F }
public sealed record PhysicalStatus(int? Battery, int FirmwareSignal, byte FirmwareMajor, byte FirmwareMinor,
    byte WorkMode, byte LightMode, ConfirmationSwitch? Confirmation, byte? Brightness, byte? ReadinessFlags);
public sealed record PhysicalCapabilities(byte? ProtocolMajor,byte? ProtocolMinor,byte? FirmwareMajor,byte? FirmwareMinor,
    byte? HardwareRevision,uint? Bits,byte? FirmwarePatch,byte? Model)
{
    public bool SupportedContract => ProtocolMajor==3 && ProtocolMinor==2 && Model==1 && (Bits & 0x7FF)==0x7FF &&
        FirmwareMajor is {} major && FirmwareMinor is {} minor && FirmwarePatch is {} patch && new Version(major,minor,patch)>=new Version(1,4,7);
}
// Pure Windows dialect facade. Only these two request frames are authorized in Phase 3.
public static class AhaKeyProtocol
{
    public static ImmutableArray<byte> Query(ReadOnlyQuery command) => command switch
    { ReadOnlyQuery.PhysicalStatus=>[0xAA,0xBB,0x00,0xCC,0xDD],ReadOnlyQuery.Capabilities=>[0xAA,0xBB,0x9F,0xCC,0xDD],_=>throw new ArgumentOutOfRangeException(nameof(command)) };
    public static bool IsAllowedQuery(ReadOnlySpan<byte> frame) => frame.Length==5 && frame[0]==0xAA && frame[1]==0xBB && (frame[2]==0 || frame[2]==0x9F) && frame[3]==0xCC && frame[4]==0xDD;
    public static bool IsFrame(ReadOnlySpan<byte> frame,ReadOnlyQuery command) => frame.Length>=5 && frame[0]==0xAA && frame[1]==0xBB && frame[2]==(byte)command && frame[^2]==0xCC && frame[^1]==0xDD;
    public static PhysicalStatus DecodeStatus(ReadOnlySpan<byte> frame)
    {
        if(!IsFrame(frame,ReadOnlyQuery.PhysicalStatus) || frame.Length is <12 or >14) throw new FormatException("Unsupported status frame.");
        return new(frame[3]<=100?frame[3]:null,unchecked((sbyte)frame[4]),frame[5],frame[6],frame[7],frame[8],
            frame[9] switch {0=>ConfirmationSwitch.Auto,1=>ConfirmationSwitch.Manual,_=>null},frame.Length>=13?frame[10]:null,frame.Length>=14?frame[11]:null);
    }
    public static PhysicalCapabilities DecodeCapabilities(ReadOnlySpan<byte> frame)
    {
        // Observed Windows device returns a status-only 9F acknowledgement. It proves no capability fields.
        if(IsFrame(frame,ReadOnlyQuery.Capabilities) && frame.Length==6 && frame[3]==0) return new(null,null,null,null,null,null,null,null);
        if(!IsFrame(frame,ReadOnlyQuery.Capabilities) || frame.Length is <15 or >17 || frame[3]!=0) throw new FormatException("Unsupported capability response.");
        var p=frame[4..^2];
        return new(p[0],p[1],p[2],p[3],p[4],System.Buffers.Binary.BinaryPrimitives.ReadUInt32LittleEndian(p[5..9]),p.Length>=10?p[9]:null,p.Length>=11?p[10]:null);
    }
}

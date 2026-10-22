using System.Collections.Immutable;
using AhaKey.Core;
namespace AhaKey.Protocol;

public sealed record ConfigResourceSlice(byte Resource,byte Index,byte Total,byte Offset,ImmutableArray<byte> Data)
{ public bool IsFullConfigurationBackup => false; public string Semantics => "Partial live RAM observation"; }
public sealed record FirmwareProtocolSemantics(string Persistence,string Readback,string DisplayGeometry,string Restrictions);
public interface IFirmwareProtocolAdapter
{
    FirmwareDialect Dialect {get;}
    FirmwareProtocolSemantics Semantics {get;}
    ImmutableArray<byte> Query(ReadOnlyQuery query);
    PhysicalStatus ParseStatus(ReadOnlySpan<byte> frame);
    PhysicalCapabilities ParseCapabilities(ReadOnlySpan<byte> frame);
    void ValidateControl(LegacyControlCommand command);
    ImmutableArray<byte> QueryConfig(byte resource,byte index,byte offset);
    ConfigResourceSlice ParseConfig(ReadOnlySpan<byte> frame,byte resource,byte index,byte offset);
}
public static class FirmwareProtocols
{
    public static FirmwareIdentity Identify(PhysicalStatus? status,PhysicalCapabilities? caps,IdentitySource source=IdentitySource.PhysicalTelemetry)
    {
        if(status is null)return FirmwareIdentity.Unknown;
        var dialect=caps is {ProtocolMajor:3,ProtocolMinor:2,Model:1}?FirmwareDialect.WindowsContract32:
            caps is {ProtocolMajor:null,ProtocolMinor:null,Model:null,Bits:null}?FirmwareDialect.LegacyWindows:FirmwareDialect.Unknown;
        return new(caps?.FirmwareMajor??status.FirmwareMajor,caps?.FirmwareMinor??status.FirmwareMinor,caps?.FirmwarePatch,
            caps?.ProtocolMajor is {} ma && caps.ProtocolMinor is {} mi?$"{ma}.{mi}":null,caps?.Model,caps?.Bits,
            $"status:{(status.ReadinessFlags is not null?14:status.Brightness is not null?13:12)};caps:{(caps?.Bits is null?"absent":"populated")};brightness:{(status.Brightness is null?"absent":"present")}",
            null,source,dialect);
    }
    public static IFirmwareProtocolAdapter For(FirmwareDialect dialect) => dialect switch
    {
        FirmwareDialect.LegacyWindows=>new LegacyWindowsProtocolAdapter(),
        FirmwareDialect.WindowsContract32=>new WindowsContract32ProtocolAdapter(),
        _=>new QuarantinedProtocolAdapter(dialect)
    };
}
public class LegacyWindowsProtocolAdapter : IFirmwareProtocolAdapter
{
    public virtual FirmwareDialect Dialect=>FirmwareDialect.LegacyWindows;
    public virtual FirmwareProtocolSemantics Semantics=>new("04 saves shared key_bund; dirty setters may save on shutdown",
        "Telemetry and known binding queries only; no full readback", "Only attested P2 Default slot9 static writer", "No generic K1, brightness or unknown targets");
    public ImmutableArray<byte> Query(ReadOnlyQuery query)=>AhaKeyProtocol.Query(query);
    public PhysicalStatus ParseStatus(ReadOnlySpan<byte> frame)=>AhaKeyProtocol.DecodeStatus(frame);
    public PhysicalCapabilities ParseCapabilities(ReadOnlySpan<byte> frame)=>AhaKeyProtocol.DecodeCapabilities(frame);
    public virtual void ValidateControl(LegacyControlCommand command)
    {
        var f=command.Frame;
        if(command.Opcode==0x73 && f.Length>5 && f[5]==0)throw new InvalidOperationException("K1 is firmware-managed F18.");
        if(command.Opcode is not (0x73 or 0x04 or 0x91 or 0x92))throw new InvalidOperationException("Operation is outside the shipping dialect restrictions.");
    }
    public virtual ImmutableArray<byte> QueryConfig(byte resource,byte index,byte offset)=>throw new NotSupportedException("No demonstrated legacy config resource read.");
    public virtual ConfigResourceSlice ParseConfig(ReadOnlySpan<byte> frame,byte resource,byte index,byte offset)=>throw new NotSupportedException();
}
// Source-defined Windows 3.2 commands; typed transport permits and live per-feature gates limit physical use.
public sealed class WindowsContract32ProtocolAdapter : LegacyWindowsProtocolAdapter
{
    public override FirmwareDialect Dialect=>FirmwareDialect.WindowsContract32;
    public override FirmwareProtocolSemantics Semantics=>new("Shared save; first-boot migration may seed assets", "9D partial live RAM; no atomic/persisted backup",
        "4 profiles x (8+12+12+12); RGB565 160x80; stride28672", "Raw F18 overrides generic K1/voice mapping");
    public override void ValidateControl(LegacyControlCommand command)
    {if(command.Opcode is 0x84 or 0x85 or 0x90)return;base.ValidateControl(command);}
    public static int ResourceLength(byte resource,byte index)=>resource switch
    {0 when index<16=>100,1 when index<4=>9,2 when index==0=>2,_=>throw new ArgumentOutOfRangeException(nameof(resource))};
    public override ImmutableArray<byte> QueryConfig(byte resource,byte index,byte offset)
    {if(offset>=ResourceLength(resource,index))throw new ArgumentOutOfRangeException(nameof(offset));return [0xAA,0xBB,0x9D,resource,index,offset,0xCC,0xDD];}
    public override ConfigResourceSlice ParseConfig(ReadOnlySpan<byte> f,byte resource,byte index,byte offset)
    {
        int total=ResourceLength(resource,index);
        if(f.Length<12 || f[0]!=0xAA || f[1]!=0xBB || f[2]!=0x9D || f[3]!=0 || f[4]!=resource || f[5]!=index ||
            f[6]!=total || f[7]!=offset || f[8] is <1 or >8 || f[8]!=Math.Min(8,total-offset) || f.Length!=11+f[8] || f[^2]!=0xCC || f[^1]!=0xDD)
            throw new FormatException("Invalid partial configuration slice.");
        return new(resource,index,(byte)total,offset,[..f[9..^2]]);
    }
    public static int DisplaySlot(HardwareProfileId profile,DisplayState state)
    {if(!Enum.IsDefined(profile)||!Enum.IsDefined(state))throw new ArgumentOutOfRangeException();return Windows32DisplayGeometry.Target(profile,state).StartSlot;}
    public ImmutableArray<byte> TaskSlot(byte slot,HardwareProfileId profile,byte state,byte flags)
    {if(slot>=4||!Enum.IsDefined(profile)||state>4||flags>1)throw new ArgumentOutOfRangeException();return [0xAA,0xBB,0x99,slot,(byte)profile,state,flags,0xCC,0xDD];}
}
public sealed class QuarantinedProtocolAdapter(FirmwareDialect dialect) : IFirmwareProtocolAdapter
{
    public FirmwareDialect Dialect=>dialect;
    public FirmwareProtocolSemantics Semantics=>new("Unknown","Unavailable","Unknown ownership","No commands from quarantined adapter");
    private static NotSupportedException Refusal()=>new("Unknown/runtime dialect is quarantined; conflicting opcodes cannot be emitted.");
    public ImmutableArray<byte> Query(ReadOnlyQuery query)=>throw Refusal();
    public PhysicalStatus ParseStatus(ReadOnlySpan<byte> frame)=>throw Refusal();
    public PhysicalCapabilities ParseCapabilities(ReadOnlySpan<byte> frame)=>throw Refusal();
    public void ValidateControl(LegacyControlCommand command)=>throw Refusal();
    public ImmutableArray<byte> QueryConfig(byte resource,byte index,byte offset)=>throw Refusal();
    public ConfigResourceSlice ParseConfig(ReadOnlySpan<byte> frame,byte resource,byte index,byte offset)=>throw Refusal();
}

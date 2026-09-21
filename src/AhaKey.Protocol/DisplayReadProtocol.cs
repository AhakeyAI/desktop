using System.Collections.Immutable;
using System.Buffers.Binary;
namespace AhaKey.Protocol;

public enum DisplayResponseKind { SUPPORTED_POPULATED, EMPTY_SUCCESS_ACK, EXPLICIT_UNSUPPORTED, TIMEOUT, MALFORMED, UNKNOWN }
public enum EvidenceComparison { MATCH, MISMATCH, NOT_REPORTED }
public sealed record DisplayLayout(byte Profiles,byte AssetsPerProfile,byte MaxFrames,ushort BytesPerFrame,
    byte SectorsPerFrame,byte Width,byte Height,ushort? FlashId,uint? PhysicalFlashBytes,ushort? PhysicalFrameSlots,ImmutableArray<byte>? AssetCapacities)
{
    public EvidenceComparison CapacityComparison=>PhysicalFlashBytes is null?EvidenceComparison.NOT_REPORTED:PhysicalFlashBytes==8_388_608?EvidenceComparison.MATCH:EvidenceComparison.MISMATCH;
    public EvidenceComparison DimensionsComparison=>Width==160 && Height==80?EvidenceComparison.MATCH:EvidenceComparison.MISMATCH;
}
public sealed record DisplayBinding(byte Profile,byte? State,ushort Start,ushort Count,ushort IntervalMs,ushort TotalFrameSlots);
public sealed record DisplayReadResponse(DisplayResponseKind Classification,byte? Status=null,DisplayLayout? Layout=null,DisplayBinding? Binding=null,PhysicalStatus? Telemetry=null);

// Independently source-gated, exact Phase 3.5 requests. Not part of normal ReadOnlyQuery.
public static class DisplayReadProtocol
{
    public const int QueryCount=5;
    public static ImmutableArray<byte> Request(int index)=>index switch
    {0 or 4=>[0xAA,0xBB,0,0xCC,0xDD],1=>[0xAA,0xBB,0x9C,0xCC,0xDD],2=>[0xAA,0xBB,0x83,0,0xCC,0xDD],3=>[0xAA,0xBB,0x94,0,1,0xCC,0xDD],_=>throw new ArgumentOutOfRangeException(nameof(index))};
    public static ImmutableArray<byte> Report(int index)
    {var request=Request(index);var bytes=new byte[65];bytes[1]=0xA1;bytes[2]=(byte)request.Length;request.CopyTo(bytes,3);return bytes.ToImmutableArray();}
    public static bool IsApprovedReport(ReadOnlySpan<byte> report)
    {for(int i=0;i<QueryCount;i++)if(Report(i).AsSpan().SequenceEqual(report))return true;return false;}
    public static DisplayReadResponse Parse(byte command,ReadOnlySpan<byte> frame,byte expectedProfile=0)
    {
        if(frame.Length<6 || frame[0]!=0xAA || frame[1]!=0xBB || frame[^2]!=0xCC || frame[^1]!=0xDD)return new(DisplayResponseKind.MALFORMED);
        if(frame[2]!=command || command is not (0 or 0x9C or 0x83 or 0x94))return new(DisplayResponseKind.UNKNOWN);
        if(command==0)
        {try{return new(DisplayResponseKind.SUPPORTED_POPULATED,Telemetry:AhaKeyProtocol.DecodeStatus(frame));}catch(FormatException){return new(DisplayResponseKind.MALFORMED);}}
        byte status=frame[3];if(status!=0)return new(status==3?DisplayResponseKind.EXPLICIT_UNSUPPORTED:DisplayResponseKind.UNKNOWN,status);
        var p=frame[4..^2];if(p.Length==0)return new(DisplayResponseKind.EMPTY_SUCCESS_ACK,0);
        static ushort U16(ReadOnlySpan<byte> b,int at)=>BinaryPrimitives.ReadUInt16LittleEndian(b[at..]);
        if(command==0x9C)
        {
            if(p.Length<8 || !(p.Length is 8 or 10 or 14 or 16 || p.Length==16+p[1]) || p[0]==0 || p[1]==0)return new(DisplayResponseKind.MALFORMED,0);
            return new(DisplayResponseKind.SUPPORTED_POPULATED,0,new(p[0],p[1],p[2],U16(p,3),p[5],p[6],p[7],
                p.Length>=10?U16(p,8):null,p.Length>=14?BinaryPrimitives.ReadUInt32LittleEndian(p[10..]):null,
                p.Length>=16?U16(p,14):null,p.Length==16+p[1]?p[16..].ToArray().ToImmutableArray():null));
        }
        int expected=command==0x83?9:10;if(p.Length!=expected)return new(DisplayResponseKind.MALFORMED,0);
        if(expectedProfile>3 || p[0]!=expectedProfile || command==0x94 && p[1]!=1)return new(DisplayResponseKind.UNKNOWN,0);
        int offset=command==0x83?1:2;
        return new(DisplayResponseKind.SUPPORTED_POPULATED,0,Binding:new(p[0],command==0x94?p[1]:null,U16(p,offset),U16(p,offset+2),U16(p,offset+4),U16(p,offset+6)));
    }
}

// Consumes attempts before native I/O: errors cannot reset the budget or replay a query.
public sealed class DisplayCharacterizationGuard(bool defaultBindings=false)
{
    private int next;
    private readonly object sync=new();
    public int Attempts {get {lock(sync)return next;}}
    public int QueryCount=>defaultBindings?6:DisplayReadProtocol.QueryCount;
    public ImmutableArray<byte> Request(int index)=>!defaultBindings?DisplayReadProtocol.Request(index):index switch
    {0 or 5=>[0xAA,0xBB,0,0xCC,0xDD],>=1 and <=4=>[0xAA,0xBB,0x83,(byte)(index-1),0xCC,0xDD],_=>throw new ArgumentOutOfRangeException(nameof(index))};
    public ImmutableArray<byte> Report(int index)
    {var request=Request(index);var bytes=new byte[65];bytes[1]=0xA1;bytes[2]=(byte)request.Length;request.CopyTo(bytes,3);return bytes.ToImmutableArray();}
    public bool IsApprovedReport(ReadOnlySpan<byte> report)
    {for(int i=0;i<QueryCount;i++)if(Report(i).AsSpan().SequenceEqual(report))return true;return false;}
    public void Consume(ReadOnlySpan<byte> report)
    {lock(sync){if(next>=QueryCount || !report.SequenceEqual(Report(next).AsSpan()))throw new InvalidOperationException("Exact one-shot display read sequence rejected.");next++;}}
}

using System.Collections.Immutable;
using System.Text;
namespace AhaKey.Device.Ble;

// Phase 3.1 only. The ordinary factory never supplies this permit. No generic config API.
public sealed class LegacyCharacterizationPermit(string attemptFile)
{
    public static ImmutableArray<byte> Request {get;}=[0xAA,0xBB,0x9D,0x02,0x00,0x00,0xCC,0xDD];
    private int consumed;
    public void Consume(ReadOnlySpan<byte> frame,Guid session)
    {
        if(!frame.SequenceEqual(Request.AsSpan())) throw new BleException("BleReadOnly","Only the fixed Phase 3.1 query is permitted.");
        if(Interlocked.Exchange(ref consumed,1)!=0) throw new BleException("BleReadOnly","Phase 3.1 query already attempted; no retry.");
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(attemptFile))!);
        // Durable before the native call. Existing/uncertain attempts fail closed across processes.
        using var file=new FileStream(attemptFile,FileMode.CreateNew,FileAccess.Write,FileShare.None);
        file.Write(Encoding.UTF8.GetBytes($"Session={session}\nReservedAt={DateTimeOffset.UtcNow:O}\nTX=AA BB 9D 02 00 00 CC DD\nNo retry, even if transmission outcome is uncertain.\n"));
        file.Flush(true);
    }
}

public enum LegacyQueryResult { SUPPORTED_NEWER_FORMAT, SUPPORTED_LEGACY_FORMAT, UNSUPPORTED_COMMAND, TIMEOUT, UNKNOWN_RESPONSE }
public static class LegacyQueryClassifier
{
    public static LegacyQueryResult Classify(ReadOnlySpan<byte> frame,bool timeout=false)
    {
        if(timeout)return LegacyQueryResult.TIMEOUT;
        if(frame.Length<6 || frame[0]!=0xAA || frame[1]!=0xBB || frame[2]!=0x9D || frame[^2]!=0xCC || frame[^1]!=0xDD)return LegacyQueryResult.UNKNOWN_RESPONSE;
        if(frame.Length==6 && frame[3]==3)return LegacyQueryResult.UNSUPPORTED_COMMAND;
        if(frame[3]!=0)return LegacyQueryResult.UNKNOWN_RESPONSE;
        var p=frame[4..^2];
        if(p.Length==7 && p[0]==2 && p[1]==0 && p[2]==2 && p[3]==0 && p[4]==2)return LegacyQueryResult.SUPPORTED_NEWER_FORMAT;
        // Historical Windows 37dd12f uses 9D for capability replies (9..11 payload bytes).
        if(p.Length is >=9 and <=11)return LegacyQueryResult.SUPPORTED_LEGACY_FORMAT;
        // A success-only ACK also exists for unrecognized commands in historical firmware.
        return LegacyQueryResult.UNKNOWN_RESPONSE;
    }
}

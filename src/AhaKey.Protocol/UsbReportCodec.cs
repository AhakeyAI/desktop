using System.Collections.Immutable;
namespace AhaKey.Protocol;

// Windows HID lengths include a report-ID byte even when the descriptor has no IDs.
public static class UsbReportCodec
{
    public const int PayloadLength = 64;
    public const int NativeLength = 65;
    public static ImmutableArray<byte> EncodeQuery(ReadOnlyQuery query)
    {
        var command = AhaKeyProtocol.Query(query);
        var report = new byte[NativeLength];
        report[1] = 0xA1; report[2] = (byte)command.Length;
        command.CopyTo(report, 3);
        return ImmutableArray.Create(report);
    }
    public static bool IsAllowedReport(ReadOnlySpan<byte> report) =>
        report.Length == NativeLength && report[0] == 0 && report[1] == 0xA1 && report[2] == 5 &&
        AhaKeyProtocol.IsAllowedQuery(report.Slice(3, 5)) && report[8..].IndexOfAnyExcept((byte)0) < 0;
}

// Bounded, command-aware Windows input assembler. No generic first-trailer splitting.
public sealed class UsbFrameAccumulator(bool includeDisplayReads = false, bool includeControlAcks = false,bool includeDisplayWrites=false,bool includeConfigReads=false)
{
    private readonly List<byte> bytes = [];
    public const int MaximumBufferedBytes = 256;
    public int BufferedBytes => bytes.Count;
    public void Clear() => bytes.Clear();
    public IReadOnlyList<ImmutableArray<byte>> Feed(ReadOnlySpan<byte> input)
    {
        if (input.Length > MaximumBufferedBytes || bytes.Count + input.Length > MaximumBufferedBytes)
        { bytes.Clear(); throw new FormatException("USB input accumulator limit exceeded."); }
        bytes.AddRange(input.ToArray());
        var frames = new List<ImmutableArray<byte>>();
        while (bytes.Count >= 2)
        {
            if (bytes[0] != 0xAA || bytes[1] != 0xBB) { bytes.RemoveAt(0); continue; }
            if (bytes.Count < 3) break;
            if(bytes[2]==0x9D&&includeConfigReads&&(bytes.Count<4||bytes[3]==0&&bytes.Count<9))break;
            int[] lengths = bytes[2] switch { 0 => [13, 14, 12, 6], 0x9F => [17, 16, 15, 6],
                0x73 or 0x04 or 0x91 or 0x92 or 0x85 or 0x84 or 0x90 when includeControlAcks => [6],
                0x80 or 0x81 or 0x82 or 0x93 when includeDisplayWrites => [6],
                0x9D when includeConfigReads=> bytes.Count>=9&&bytes[3]==0&&bytes[8] is >=1 and <=8?[11+bytes[8]]:[6],
                0x83 when includeDisplayReads => [15,6],0x94 when includeDisplayReads => [16,6],
                0x9C when includeDisplayReads => bytes.Count>=6 && bytes[5] is >0 and <=32 ? [22+bytes[5],22,20,16,14,6] : [22,20,16,14,6],_ => [] };
            if (lengths.Length == 0) { bytes.RemoveAt(0); continue; }
            var length = lengths.FirstOrDefault(n => bytes.Count >= n && bytes[n-2] == 0xCC && bytes[n-1] == 0xDD &&
                (bytes.Count == n || bytes[n] == 0 || bytes[n] == 0xAA));
            if (length == 0)
            {
                if (bytes.Count < lengths.Max()) break;
                bytes.RemoveAt(0); continue;
            }
            frames.Add(bytes.Take(length).ToImmutableArray()); bytes.RemoveRange(0, length);
        }
        // Inter-report zero fill is never retained as a new frame prefix.
        if (bytes.Count == 1 && bytes[0] != 0xAA) bytes.Clear();
        return frames;
    }
    public IReadOnlyList<ImmutableArray<byte>> FeedReport(ReadOnlySpan<byte> report)
    {
        if (report.Length is < 1 or > UsbReportCodec.NativeLength || report[0] != 0)
            throw new FormatException("Unexpected HID report ID/length.");
        return Feed(report[1..]);
    }
}

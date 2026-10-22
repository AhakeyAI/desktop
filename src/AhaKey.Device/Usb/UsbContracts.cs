using System.Collections.Immutable;
using AhaKey.Protocol;
namespace AhaKey.Device.Usb;

public sealed record HidCandidate(string Path, string InstanceId, ushort Vid, ushort Pid,
    int? InterfaceNumber, int? Collection, ushort UsagePage, ushort Usage,
    ushort InputLength, ushort OutputLength, ushort FeatureLength,
    ImmutableArray<byte> InputIds, ImmutableArray<byte> OutputIds, string? Manufacturer, string? Product,
    string? InspectionError = null)
{
    public string DisplayName => "AhaKey USB device"; // Never infer a Bluetooth identity from VID/PID.
}
public sealed class UsbException(string key, string message) : IOException(message) { public string Key { get; } = key; }
public sealed record HidSelection(HidCandidate? Candidate, string? ErrorKey);
public static class HidSelectionPolicy
{
    public static bool IsValid(HidCandidate c) => c.InspectionError is null && c.Vid == 0x413C && c.Pid == 0x2107 &&
        (c.InterfaceNumber == 1 || c.Collection == 2) && c.UsagePage == 0xFF00 && c.Usage == 1 &&
        c.InputLength == 65 && c.OutputLength == 65 && c.FeatureLength == 0 &&
        c.InputIds.SequenceEqual(new byte[] { 0 }) && c.OutputIds.SequenceEqual(new byte[] { 0 });
    public static HidSelection Select(IReadOnlyList<HidCandidate> candidates)
    {
        var valid = candidates.Where(IsValid).ToArray();
        return valid.Length switch { 1 => new(valid[0], null), > 1 => new(null, "UsbAmbiguous"),
            _ => new(null, candidates.Count == 0 ? "UsbNotFound" : "UsbUnidentified") };
    }
    public static void Require(HidCandidate c)
    { if (!IsValid(c)) throw new UsbException("UsbUnidentified", "HID collection/report contract is not identified safely."); }
}
public sealed record HidInput(Guid SessionId, DateTimeOffset At, ImmutableArray<byte> Report);
public sealed record HidWriteResult(bool Success, int BytesWritten, int Error);
public interface IWindowsHidSession : IAsyncDisposable
{
    Guid Id { get; }
    bool ReaderRunning { get; }
    Task OpenAsync(HidCandidate candidate, Action<HidInput> input, Action<Guid,Exception> failed, CancellationToken ct);
    Task<HidWriteResult> WriteConfigAsync(ApprovedConfigRead query,CancellationToken ct)=>throw new NotSupportedException();
    Task<HidWriteResult> WriteControlAsync(ApprovedControl control,CancellationToken ct) => throw new NotSupportedException("Physical controls unavailable in this session.");
    Task<HidWriteResult> WriteDisplayAsync(ApprovedDisplayReport report,CancellationToken ct) => throw new NotSupportedException("Physical Display unavailable in this session.");
    Task<HidWriteResult> WriteAsync(ImmutableArray<byte> report, CancellationToken ct);
    void Cancel();
}
public interface IWindowsHidSessionFactory
{
    Task<IReadOnlyList<HidCandidate>> EnumerateAsync(CancellationToken ct);
    IWindowsHidSession Create(Guid id);
}
public sealed record UsbHistory(DateTimeOffset At, Guid? Session, string Event, string Detail);
public sealed record UsbQueryEvidence(Guid SessionId, ReadOnlyQuery Command, DateTimeOffset WriteStartedAt,
    DateTimeOffset WriteCompletedAt, DateTimeOffset ResponseAt, ImmutableArray<byte> CommandBytes,
    ImmutableArray<byte> OutputReport, HidWriteResult Result, ImmutableArray<ImmutableArray<byte>> InputReports,
    ImmutableArray<byte> Frame)
{ public double LatencyMs => (ResponseAt - WriteStartedAt).TotalMilliseconds; }
public sealed record UsbDiagnostics
{
    public string Stage { get; init; } = "Disconnected";
    public Guid? SessionId { get; init; }
    public HidCandidate? Selected { get; init; }
    public IReadOnlyList<HidCandidate> Candidates { get; init; } = [];
    public bool IsLive { get; init; }
    public bool ReaderRunning { get; init; }
    public PhysicalStatus? Status { get; init; }
    public PhysicalCapabilities? Capabilities { get; init; }
    public DateTimeOffset? StatusAt { get; init; }
    public UsbQueryEvidence? LastQuery { get; init; }
    public UsbQueryEvidence? LastStatusQuery { get; init; }
    public ImmutableArray<byte> LastInput { get; init; } = [];
    public ImmutableArray<byte> LastOutput { get; init; } = [];
    public HidWriteResult? LastWriteResult { get; init; }
    public string? ErrorKey { get; init; }
    public string? Error { get; init; }
    public ImmutableArray<UsbHistory> History { get; init; } = [];
}

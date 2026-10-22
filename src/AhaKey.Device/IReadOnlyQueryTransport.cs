using System.Collections.Immutable;
using AhaKey.Protocol;
namespace AhaKey.Device;
public enum PhysicalTransportKind { Bluetooth, Usb }
public sealed record PhysicalQueryEvidence(PhysicalTransportKind Transport, Guid SessionId, ReadOnlyQuery Command,
    DateTimeOffset StartedAt, DateTimeOffset CompletedAt, DateTimeOffset ResponseAt,
    ImmutableArray<byte> Tx, ImmutableArray<byte> Rx);
public sealed record PhysicalObservation(PhysicalTransportKind Transport, Guid? SessionId, bool IsLive,
    PhysicalStatus? Status, PhysicalCapabilities? Capabilities, DateTimeOffset? StatusAt, string? ErrorKey);
// No native handles, GATT packets or HID reports escape into the real device/domain contract.
public interface IReadOnlyQueryTransport
{
    PhysicalObservation Observation { get; }
    Task<PhysicalQueryEvidence> QueryFrameAsync(ReadOnlyQuery command, CancellationToken ct);
    void AcceptStatus(PhysicalQueryEvidence query, PhysicalStatus status);
    void AcceptCapabilities(PhysicalQueryEvidence query, PhysicalCapabilities capabilities);
}

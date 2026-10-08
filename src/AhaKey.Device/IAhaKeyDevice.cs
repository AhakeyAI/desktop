using AhaKey.Core;
namespace AhaKey.Device;
public enum MockFailure { None, ConnectionFailure, Timeout, WriteFailure, InvalidResponse, DeviceBusy, DisconnectDuringWrite }
public sealed class DeviceOperationException(MockFailure failure) : Exception(failure.ToString())
{
    public MockFailure Failure { get; } = failure;
    public bool IsIndeterminate => Failure is MockFailure.Timeout or MockFailure.InvalidResponse or MockFailure.DisconnectDuringWrite;
}
public interface IAhaKeyDevice
{
    DeviceIdentity Identity { get; }
    DeviceCapabilities Capabilities { get; }
    DeviceStatus Status { get; }
    Task ConnectAsync(CancellationToken cancellationToken = default);
    Task DisconnectAsync(CancellationToken cancellationToken = default);
    Task<ConfigurationSnapshot> ReadAsync(CancellationToken cancellationToken = default);
    Task WriteAsync(DeviceConfiguration configuration, CancellationToken cancellationToken = default);
}

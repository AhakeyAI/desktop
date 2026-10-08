using AhaKey.Core;
namespace AhaKey.Device;
public sealed class MockAhaKeyDevice(TimeProvider? clock = null) : IAhaKeyDevice, IActionSimulator
{
    private readonly TimeProvider clock = clock ?? TimeProvider.System;
    private DeviceConfiguration configuration = DeviceConfiguration.Default;
    private int sessionSequence;
    public DeviceIdentity Identity { get; } = new("AhaKey AE1E", "Simulation / Phase 1", true);
    public DeviceCapabilities Capabilities { get; } = new(true);
    public DeviceStatus Status { get; private set; } = new(ConnectionState.Disconnected, null, null, null);
    public MockFailure NextFailure { get; set; }
    public TimeSpan Latency { get; init; } = TimeSpan.FromMilliseconds(120);
    public int SimulatedBattery { get; private set; } = 91;
    public ConfirmationSwitch SimulatedSwitch { get; private set; } = ConfirmationSwitch.Manual;
    public void SetTelemetry(int battery, ConfirmationSwitch confirmation)
    {
        if (battery is < 0 or > 100 || !Enum.IsDefined(confirmation)) throw new ArgumentOutOfRangeException(nameof(battery));
        SimulatedBattery = battery; SimulatedSwitch = confirmation;
        if (Status.SessionId is not null) Status = Status with { Battery = battery, Confirmation = confirmation };
    }
    public async Task ConnectAsync(CancellationToken cancellationToken = default)
    {
        Status = Status with { Connection = ConnectionState.Connecting };
        try
        {
            await Pause(cancellationToken); ThrowFailure(false, true);
            Status = new(ConnectionState.Connected, SimulatedBattery, SimulatedSwitch, new Guid(++sessionSequence, 0, 0, new byte[8]));
        }
        catch { Status = new(ConnectionState.Disconnected, null, null, null); throw; }
    }
    public Task DisconnectAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Status = new(ConnectionState.Disconnected, null, null, null); return Task.CompletedTask;
    }
    public async Task<ConfigurationSnapshot> ReadAsync(CancellationToken cancellationToken = default)
    {
        var session = RequireSession(); await Pause(cancellationToken); ThrowFailure(false, false);
        if (Status.SessionId != session) throw new DeviceOperationException(MockFailure.DisconnectDuringWrite);
        return new(configuration, SnapshotSource.MockRead, session, Identity, clock.GetUtcNow());
    }
    public async Task WriteAsync(DeviceConfiguration draft, CancellationToken cancellationToken = default)
    {
        var session = RequireSession(); Capabilities.Validate(draft);
        await Pause(cancellationToken); ThrowFailure(true, false);
        if (Status.SessionId != session) throw new DeviceOperationException(MockFailure.DisconnectDuringWrite);
        configuration = draft;
    }
    public SimulatedActionResult TestAction(PhysicalKey key, KeyAction action)
    {
        if(!Capabilities.Supports(key,action)) throw new ArgumentException("Unsupported simulated action.");
        return new(action); // No input injection, device write, or sync mutation.
    }
    private Task Pause(CancellationToken ct) => Task.Delay(Latency, clock, ct);
    private Guid RequireSession() => Status.SessionId ?? throw new InvalidOperationException("Mock is disconnected.");
    private void ThrowFailure(bool write, bool connect)
    {
        var failure = NextFailure;
        if (failure == MockFailure.None || (failure == MockFailure.ConnectionFailure && !connect) ||
            (failure is MockFailure.WriteFailure or MockFailure.DisconnectDuringWrite && !write)) return;
        NextFailure = MockFailure.None;
        if (failure == MockFailure.DisconnectDuringWrite) Status = new(ConnectionState.Disconnected, null, null, null);
        throw new DeviceOperationException(failure);
    }
}

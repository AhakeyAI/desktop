using AhaKey.Core;
namespace AhaKey.Device;
public sealed class DeviceStateMachine
{
    public ConnectionState State { get; private set; } = ConnectionState.Disconnected;
    public void MoveTo(ConnectionState next)
    {
        bool valid = (State, next) switch
        {
            (_, ConnectionState.Disconnected) => true,
            (ConnectionState.Disconnected or ConnectionState.Error, ConnectionState.Connecting) => true,
            (ConnectionState.Connecting, ConnectionState.Connected or ConnectionState.Error) => true,
            (ConnectionState.Connected, ConnectionState.ReadingConfiguration or ConnectionState.WritingConfiguration) => true,
            (ConnectionState.ReadingConfiguration or ConnectionState.WritingConfiguration, ConnectionState.Connected or ConnectionState.Error or ConnectionState.Busy) => true,
            (ConnectionState.Busy, ConnectionState.Connected) => true,
            _ => false
        };
        if (!valid) throw new InvalidOperationException($"Illegal device transition: {State} → {next}");
        State = next;
    }
}

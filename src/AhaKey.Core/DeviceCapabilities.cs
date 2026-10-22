namespace AhaKey.Core;
public sealed record DeviceCapabilities(bool IsSimulation, bool PhysicalDisplayUploadAvailable = false,
    bool ArbitraryK1Remapping = false)
{
    public bool Supports(PhysicalKey key, KeyAction action) => key switch
    {
        PhysicalKey.K1 => action is VoiceInputAction { Binding: "F18" },
        PhysicalKey.K2 or PhysicalKey.K3 or PhysicalKey.K4 => action is KeyboardShortcutAction or MacroAction or DisabledAction,
        _ => false
    };
    public void Validate(DeviceConfiguration configuration)
    {
        if (configuration.GlobalBrightness is < 1 or > 100 || configuration.Profiles.Count != 4 ||
            Enum.GetValues<HardwareProfileId>().Any(id => !configuration.Profiles.ContainsKey(id)))
            throw new ArgumentException("Invalid global brightness or profile slots.");
        foreach (var p in configuration.Profiles.Values)
        {
            if (p.Keys.Count != 4 || Enum.GetValues<PhysicalKey>().Any(k => !p.Keys.ContainsKey(k)) || p.Keys.Any(k => !Supports(k.Key, k.Value)))
                throw new ArgumentException("Unsupported key configuration; K1 is the fixed F18 voice path.");
            if (p.DeviceLabels.Any(x => x.Key == PhysicalKey.K1 || !Enum.IsDefined(x.Key) || !DeviceLabelRules.IsValid(x.Value)))
                throw new ArgumentException("Device labels require K2-K4 and at most 20 printable ASCII characters.");
            if (p.Keys.Values.OfType<KeyboardShortcutAction>().Any(x => !ShortcutGesture.TryParse(x.Shortcut, out _)))
                throw new ArgumentException("Invalid keyboard shortcut.");
            if (p.Display.Count != 4 || Enum.GetValues<DisplayState>().Any(s => !p.Display.ContainsKey(s)) ||
                p.Display.Any(o => o.Value.FrameCount < 0 || o.Value.FrameCount > DisplayLimits.MaximumFrames(o.Key) || o.Value.DurationMs < 0))
                throw new ArgumentException("Invalid Display state allocation.");
            if (p.Lighting.Mapping.Count != 9 || Enum.GetValues<IdeEventState>().Any(s => !p.Lighting.Mapping.ContainsKey(s)) || p.Lighting.Mapping.Any(m => m.Value > 0x10))
                throw new ArgumentException("Invalid lighting mapping.");
        }
    }
}
public enum ConnectionState { Disconnected, Discovering, Connecting, Connected, ReadingConfiguration, WritingConfiguration, Busy, FirmwareMode, Error }
public enum ConfirmationSwitch { Manual, Auto }
public sealed record DeviceIdentity(string Name, string Firmware, bool IsSimulation);
public sealed record DeviceStatus(ConnectionState Connection, int? Battery, ConfirmationSwitch? Confirmation, Guid? SessionId);
public enum SnapshotSource { MockRead, MockWriteAccepted, DeviceRead, DeviceWriteAccepted }
public sealed record ConfigurationSnapshot(DeviceConfiguration Configuration, SnapshotSource Source,
    Guid SessionId, DeviceIdentity Identity, DateTimeOffset CapturedAt);
public enum SyncState { Synced, UnsavedChanges, Writing, WriteAccepted, WriteFailed, Indeterminate }

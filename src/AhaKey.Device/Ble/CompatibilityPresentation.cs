namespace AhaKey.Device.Ble;
public enum CompatibilityState { Unknown, LegacyTelemetryOnly, SupportedReadOnly }
public static class CompatibilityPresentation
{
    public static CompatibilityState State(BleDiagnostics d)=>d.PhysicalStatus is null ? CompatibilityState.Unknown : CompatibilityState.LegacyTelemetryOnly;
    // Even a complete 9F does not prove configuration resource readback. No upgrade/write capability is inferred.
    public static bool CanWritePhysicalConfiguration=>false;
}

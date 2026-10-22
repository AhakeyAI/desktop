namespace AhaKey.Device;
public sealed record DeviceReadiness(bool BleLink,bool GattReady,bool UsbReady,bool? HidReady,bool FreshTelemetry)
{
    // No physical timer: freshness ages locally. 00 is explicit/event-driven because it wakes firmware activity.
    public static DeviceReadiness From(PhysicalObservation observation,bool bleLink,bool subscribed,DateTimeOffset now)=>
        new(bleLink,observation.Transport==PhysicalTransportKind.Bluetooth&&observation.IsLive&&subscribed,
            observation.Transport==PhysicalTransportKind.Usb&&observation.IsLive,
            observation.Status?.ReadinessFlags is {} flags?(flags&2)!=0:null,
            observation.IsLive&&observation.StatusAt is {} at&&at<=now&&now-at<TimeSpan.FromSeconds(60));
    public static bool AutomaticTelemetryPolling=>false;
}

namespace AhaKey.Protocol;
// No packet encoders or transports in Phase 1. Audit facts are constraints, not guessed wire support.
public static class Phase1ProtocolBoundary
{
    public const bool RealCommunicationAvailable = false;
    public const bool WindowsProductionDisplayRequiresUsb = true;
    public const string ConfigurationReadbackSchema = "Unavailable: persistent 0x9D schema requires evidence";
}

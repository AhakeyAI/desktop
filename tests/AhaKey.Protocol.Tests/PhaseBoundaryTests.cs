using AhaKey.Core;
using AhaKey.Protocol;
namespace AhaKey.Protocol.Tests;
public class PhaseBoundaryTests
{
    [Fact] public void FoundationCannotClaimPhysicalTransportOrBleDisplayUpload()
    { Assert.False(Phase1ProtocolBoundary.RealCommunicationAvailable); Assert.True(Phase1ProtocolBoundary.WindowsProductionDisplayRequiresUsb); Assert.False(new DeviceCapabilities(true).PhysicalDisplayUploadAvailable); }
    [Fact] public void UnknownReadbackSchemaRemainsExplicitlyUnavailable() => Assert.StartsWith("Unavailable",Phase1ProtocolBoundary.ConfigurationReadbackSchema);
}

using AhaKey.Core;
namespace AhaKey.Core.Tests;
public sealed class Phase8FeatureTests
{
    private static readonly FirmwareIdentity Modern=new(1,4,8,"3.2",1,0x7FF,"physical",null,IdentitySource.PhysicalTelemetry,FirmwareDialect.WindowsContract32);
    [Fact] public void ModernFeaturesNeedNoLegacyReceipt()
    {
        var catalog=new DeviceFeatureCatalog(Modern,FeatureTransport.Usb,new());
        Assert.True(catalog.CanWriteShortcut(HardwareProfileId.Cursor,PhysicalKey.K4).Available);
        Assert.False(catalog.CanWriteShortcut(HardwareProfileId.Codex,PhysicalKey.K1).Available);
        Assert.True(catalog.CanSetBrightness().Available);Assert.True(catalog.CanReadConfigResource(0).Available);
        for(byte effect=0;effect<=16;effect++)Assert.True(catalog.CanUseRuntimeLighting(effect).Available);
        Assert.False(catalog.CanUseRuntimeLighting(17).Available);Assert.False(catalog.FullReadback.Available);
    }
    [Fact] public void MissingBitsBlockReadbackAndDisplayWhileBleSupportsDailyCommands()
    {
        var absent=new DeviceFeatureCatalog(Modern with{ReportedCapabilities=0},FeatureTransport.Usb,new());
        Assert.False(absent.CanReadConfigResource(0).Available);Assert.False(absent.CanUploadDisplay(HardwareProfileId.Codex,DisplayState.Default,8).Available);
        var ble=new DeviceFeatureCatalog(Modern,FeatureTransport.Bluetooth,new());Assert.True(ble.CanWriteShortcut(HardwareProfileId.Codex,PhysicalKey.K2).Available);Assert.True(ble.CanUseRuntimeLighting(16).Available);
    }
}

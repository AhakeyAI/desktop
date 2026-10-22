using AhaKey.Core;
namespace AhaKey.Core.Tests;
public sealed class Phase9FeatureTests
{
    private static readonly FirmwareIdentity Modern=new(1,4,8,"3.2",1,0x7FF,"physical",null,IdentitySource.PhysicalTelemetry,FirmwareDialect.WindowsContract32);
    [Fact] public void BleDailyOperationsDoNotDependOnUsbWhileDisplayRemainsUsb()
    {
        var ble=new DeviceFeatureCatalog(Modern,FeatureTransport.Bluetooth,new());
        foreach(var key in new[]{PhysicalKey.K2,PhysicalKey.K3,PhysicalKey.K4})Assert.True(ble.CanWriteShortcut(HardwareProfileId.Codex,key).Available);
        Assert.True(ble.CanSetBrightness().Available);for(byte r=0;r<3;r++)Assert.True(ble.CanReadConfigResource(r).Available);
        Assert.False(ble.CanReadConfigResource(3).Available);Assert.False(ble.CanWriteShortcut(HardwareProfileId.Codex,PhysicalKey.K1).Available);
        Assert.False(ble.CanUploadDisplay(HardwareProfileId.Codex,DisplayState.Default,1).Available);
        Assert.False(ble.FullReadback.Available);
        var legacy=new DeviceFeatureCatalog(Modern with{ReportedMinor=0,ReportedPatch=null,Dialect=FirmwareDialect.LegacyWindows},FeatureTransport.Bluetooth,new());Assert.False(legacy.CanWriteShortcut(HardwareProfileId.Codex,PhysicalKey.K2).Available);
    }
}

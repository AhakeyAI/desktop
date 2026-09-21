using AhaKey.Firmware;
namespace AhaKey.Core.Tests;
public sealed class FirmwarePackageTests
{
    private const string Minimal=":0400000001020304F2\n:00000001FF\n";
    [Fact] public void ValidHexRequiresResetVectorChecksumAndEof()
    {
        Assert.Equal(4,FirmwarePackageValidator.ValidateHex(Minimal).DataBytes);
        Assert.Throws<FormatException>(()=>FirmwarePackageValidator.ValidateHex(Minimal.Replace("F2","F3")));
        Assert.Throws<FormatException>(()=>FirmwarePackageValidator.ValidateHex(Minimal.Split('\n')[0]));
        Assert.Throws<FormatException>(()=>FirmwarePackageValidator.ValidateHex(Minimal+":00000001FF"));
        Assert.Throws<FormatException>(()=>FirmwarePackageValidator.ValidateHex(Minimal.Split('\n')[0]+"\n"+Minimal));
    }
    [Fact] public async Task PreparedTransportNeverFlashesEvenWithAnAuthorizationFlag()
    {
        var coordinator=new FirmwareUpdateCoordinator(new PreparedWchIspTransport());
        Assert.False(string.IsNullOrEmpty(coordinator.AvailabilityReason));
        await Assert.ThrowsAsync<NotSupportedException>(()=>coordinator.UpdateAsync(null!,true,new Progress<string>()));
    }
}

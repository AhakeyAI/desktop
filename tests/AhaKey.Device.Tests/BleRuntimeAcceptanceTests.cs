namespace AhaKey.Device.Tests;
public class BleRuntimeAcceptanceTests
{
    [Theory][InlineData(true,false)][InlineData(false,true)][InlineData(false,false)]
    public void BothVisibleStatesAreRequired(bool on,bool off)=>Assert.False(new BleRuntimeAcceptance("ble-fixture","1.0",Guid.NewGuid(),on,off,"fixture").Matches("ble-fixture","1.0"));
    [Fact] public void ProofDoesNotTransferToUsbOtherDeviceOrFirmware()
    {
        var proof=new BleRuntimeAcceptance("ble-fixture","1.0",Guid.NewGuid(),true,true,"fixture");
        Assert.True(proof.Matches("ble-fixture","1.0"));Assert.False(proof.Matches("usb-fixture","1.0"));Assert.False(proof.Matches(null,"1.0"));Assert.False(proof.Matches("ble-fixture","1.1"));Assert.False((proof with{Session=Guid.Empty}).Matches("ble-fixture","1.0"));
    }
}

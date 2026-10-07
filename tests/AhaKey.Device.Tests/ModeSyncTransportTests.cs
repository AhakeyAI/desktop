using AhaKey.Device.Ble;
using AhaKey.Device.Usb;
using AhaKey.Protocol;
namespace AhaKey.Device.Tests;
public sealed class ModeSyncTransportTests
{
    [Fact]public async Task BleUpdatesHardwareProfileRejectsLateSessionAndKeepsDraftSeparate()
    {
        var factory=new FakeGattFactory();await using var real=new RealAhaKeyDevice(new(factory,GattContract.WindowsObserved)){Selected=new("fake","Fake",null)};
        await real.ConnectAsync();var old=factory.Sessions.Single();old.Emit([0xAA,0xBB,0x9B,0,1,1,255,0xCC,0xDD]);Assert.Equal(1,real.Observation.Status!.WorkMode);
        old.Emit([0xAA,0xBB,0x9B,0,2,2,0,0xCC,0xDD]);Assert.Equal(2,real.Observation.Status!.WorkMode);
        old.Emit([0xAA,0xBB,0x9B,0,1,1,255,0xCC,0xDD]);Assert.Equal(2,real.Observation.Status!.WorkMode);
        await real.DisconnectAsync();await real.ConnectAsync();old.Emit([0xAA,0xBB,0x9B,0,1,1,1,0xCC,0xDD]);Assert.Equal(2,real.Observation.Status!.WorkMode);
        Assert.Empty(factory.Sessions.Last().Controls);
    }
    [Fact]public async Task UsbUpdatesOnUnsolicitedModeWithNoWrites()
    {
        var factory=new FakeHidFactory();await using var transport=new UsbTransport(factory);await transport.OpenAsync();
        var query=await transport.QueryFrameAsync(ReadOnlyQuery.PhysicalStatus,default);transport.AcceptStatus(query,AhaKeyProtocol.DecodeStatus(query.Rx.AsSpan()));
        factory.Sessions.Single().Emit("AABB9B000101FFCCDD");Assert.Equal(1,transport.Observation.Status!.WorkMode);
        factory.Sessions.Single().Emit("AABB9B00020200CCDD");Assert.Equal(2,transport.Observation.Status!.WorkMode);
        factory.Sessions.Single().Emit("AABB9B00010101CCDD",Guid.NewGuid());Assert.Equal(2,transport.Observation.Status!.WorkMode);
        Assert.Single(factory.Sessions.Single().Reports);
    }
    [Fact]public async Task OtherFirmwarePatchCannotWriteEvenWithCompleteCapabilities()
    {
        var factory=new FakeGattFactory{Configure=s=>s.CapabilityResponse=FakeGatt.CapsFrame.SetItem(13,7)};
        await using var real=new RealAhaKeyDevice(new(factory,GattContract.WindowsObserved)){Selected=new("fake","Fake",null)};
        await real.ConnectAsync();Assert.False(real.WritesSupported);
        await Assert.ThrowsAsync<InvalidOperationException>(()=>real.ExecuteControlsAsync(ApprovedControlPlan.WorkProfile(real.Observation.SessionId!.Value,"fixture",AhaKey.Core.HardwareProfileId.Codex),_=>{},default));
        Assert.Empty(factory.Sessions.Single().Controls);
    }
}

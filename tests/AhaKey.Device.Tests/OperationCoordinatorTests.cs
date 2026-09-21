using AhaKey.Device;
namespace AhaKey.Device.Tests;
public sealed class OperationCoordinatorTests
{
    [Fact] public async Task UsbAndBleHaveOneOwnerAndUncertainWriteIsNeverRetried()
    {
        var gate=new DeviceOperationCoordinator();var records=new List<DeviceOperationRecord>();gate.Persist=records.Add;
        Assert.True(await gate.WaitAsync(0,default));var session=Guid.NewGuid();gate.Describe("Display upload",session,PhysicalTransportKind.Usb,true);
        Assert.False(await gate.WaitAsync(0,default));gate.Confirm("81 sector 63 / address 258048");gate.Confirm("82 binding",binding:true);gate.Fail(true);gate.Release();
        var ended=gate.Journal.Single();Assert.Equal(OperationOutcome.OutcomeUncertain,ended.Outcome);Assert.Equal(2,ended.ConfirmedSteps);Assert.Equal("81 sector 63 / address 258048",ended.LastConfirmedFlashBlock);Assert.True(ended.BindingChanged);Assert.False(ended.SaveConfirmed);Assert.Equal(session,ended.Session);
        Assert.True(await gate.WaitAsync(0,default));gate.Describe("manual read",Guid.NewGuid(),PhysicalTransportKind.Bluetooth,false);gate.Release();
        Assert.Equal(2,gate.Journal.Count);Assert.True(gate.Journal[1].Generation>ended.Generation);Assert.Single(gate.Journal,x=>x.Persistent);
    }
    [Fact] public void InterruptedPersistentRecordRetainsLastConfirmedBoundary()
    {
        var original=new DeviceOperationRecord(Guid.NewGuid(),1,Guid.NewGuid(),PhysicalTransportKind.Usb,"Display upload",true,DateTimeOffset.UtcNow,null,OperationOutcome.Running,7,"81 sector 69",false,false);
        var restored=DeviceOperationCoordinator.Recover(original);Assert.Equal(OperationOutcome.OutcomeUncertain,restored.Outcome);Assert.Equal(original.LastConfirmedStep,restored.LastConfirmedStep);
    }
    [Fact] public void FreshnessDoesNotPollOrPretendHidReady()
    {
        var now=DateTimeOffset.UtcNow;var observation=new PhysicalObservation(PhysicalTransportKind.Bluetooth,Guid.NewGuid(),true,null,null,now,null);
        var r=DeviceReadiness.From(observation,true,true,now);Assert.True(r.BleLink);Assert.True(r.GattReady);Assert.False(r.UsbReady);Assert.Null(r.HidReady);Assert.True(r.FreshTelemetry);
        Assert.False(DeviceReadiness.From(observation,true,true,now.AddMinutes(2)).FreshTelemetry);Assert.False(DeviceReadiness.AutomaticTelemetryPolling);
    }
}

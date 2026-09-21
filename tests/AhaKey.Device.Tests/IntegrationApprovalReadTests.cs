using AhaKey.Core;
using AhaKey.Device.Ble;
using AhaKey.Device.Usb;
using Microsoft.Extensions.Logging.Abstractions;
namespace AhaKey.Device.Tests;

public sealed class IntegrationApprovalReadTests
{
    [Fact] public async Task CallerDeadlineFailsClosedWhileBleQueryFinishesUnderItsOriginalOwner()
    {
        var factory=new FakeGattFactory();
        await using var device=new RealAhaKeyDevice(new(factory,GattContract.WindowsObserved){QueryTimeout=TimeSpan.FromSeconds(1)}){Selected=new("fixture","Fixture",null)};
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,device);
        await manager.SelectBackendAsync(true);await manager.ConnectAsync();var native=factory.Sessions.Single();native.Respond=false;native.Commands.Clear();
        var completed=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);manager.Changed+=()=>completed.TrySetResult();
        using var deadline=new CancellationTokenSource(30);Assert.Null(await manager.RefreshApprovalStatusAsync(deadline.Token));
        Assert.True(device.Observation.IsLive);Assert.False(native.Disposed);Assert.Null(await manager.RefreshApprovalStatusAsync(default));Assert.Single(native.Commands);
        native.Emit(FakeGatt.StatusFrame);await completed.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Assert.True(device.Observation.IsLive);Assert.False(native.Disposed);
        native.Respond=true;Assert.NotNull(await manager.RefreshApprovalStatusAsync(default));Assert.Equal(2,native.Commands.Count);
    }
    [Fact] public async Task ManagerApprovalUsesOnlyFreshStatus00AndNeverMockEvidence()
    {
        var factory=new FakeHidFactory();
        await using var device=new RealAhaKeyDevice(new(new FakeGattFactory(),GattContract.WindowsObserved),new UsbTransport(factory));
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new ConfigurationChangeTracker(),NullLogger<DeviceManager>.Instance,device);
        await manager.ConnectAsync();Assert.Null(await manager.RefreshApprovalStatusAsync(default));
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);await manager.ConnectAsync();
        var session=Assert.Single(factory.Sessions);session.Reports.Clear();
        var started=DateTimeOffset.UtcNow;var observation=await manager.RefreshApprovalStatusAsync(default);
        Assert.NotNull(observation);Assert.True(observation.IsLive);Assert.True(observation.StatusAt>=started);
        var report=Assert.Single(session.Reports);Assert.Equal((byte)0,report[5]);Assert.Equal((byte)0xA1,report[1]);
        await manager.DisconnectAsync();Assert.Null(await manager.RefreshApprovalStatusAsync(default));Assert.Single(session.Reports);
    }
    [Fact] public async Task TimeoutCannotReturnCachedAutoEvidence()
    {
        var factory=new FakeHidFactory();
        await using var device=new RealAhaKeyDevice(new(new FakeGattFactory(),GattContract.WindowsObserved),new UsbTransport(factory));
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new ConfigurationChangeTracker(),NullLogger<DeviceManager>.Instance,device);
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);await manager.ConnectAsync();
        factory.Sessions[0].Respond=false;using var timeout=new CancellationTokenSource(30);
        Assert.Null(await manager.RefreshApprovalStatusAsync(timeout.Token));
    }
}

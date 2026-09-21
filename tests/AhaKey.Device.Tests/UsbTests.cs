using System.Collections.Immutable;
using AhaKey.Core;
using AhaKey.Device.Ble;
using AhaKey.Device.Usb;
using AhaKey.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
namespace AhaKey.Device.Tests;

public sealed class FakeHidFactory : IWindowsHidSessionFactory
{
    public static HidCandidate Valid=new("private-path","private-instance",0x413C,0x2107,1,null,0xFF00,1,65,65,0,[0],[0],null,null);
    public IReadOnlyList<HidCandidate> Candidates=[Valid];
    public List<FakeHid> Sessions=[];
    public Action<FakeHid>? Configure;
    public Task<IReadOnlyList<HidCandidate>> EnumerateAsync(CancellationToken ct){ct.ThrowIfCancellationRequested();return Task.FromResult(Candidates);}
    public IWindowsHidSession Create(Guid id){var s=new FakeHid(id);Configure?.Invoke(s);Sessions.Add(s);return s;}
}
public sealed class FakeHid(Guid id) : IWindowsHidSession
{
    public Guid Id=>id;
    public bool ReaderRunning {get;private set;}
    public bool Disposed;
    public bool Respond=true;
    public HidWriteResult Result=new(true,65,0);
    public Action<HidInput>? Receive;
    public Action<Guid,Exception>? Failure;
    public List<ImmutableArray<byte>> Reports=[];
    public Action? OnOpen;
    public Func<CancellationToken,Task>? Writing;
    public Task OpenAsync(HidCandidate c,Action<HidInput> input,Action<Guid,Exception> failed,CancellationToken ct){OnOpen?.Invoke();ReaderRunning=true;Receive=input;Failure=failed;return Task.CompletedTask;}
    public async Task<HidWriteResult> WriteAsync(ImmutableArray<byte> r,CancellationToken ct)
    {Assert.True(UsbReportCodec.IsAllowedReport(r.AsSpan()));Reports.Add(r);if(Writing is not null)await Writing(ct);if(Respond)Emit(r[5]==0?"AABB004B32010002000023CCDD":"AABB9F00CCDD");return Result;}
    public void Emit(string hex,Guid? id=null){var r=new byte[65];Convert.FromHexString(hex).CopyTo(r,1);Receive?.Invoke(new(id??Id,DateTimeOffset.UtcNow,r.ToImmutableArray()));}
    public void Cancel() { }
    public ValueTask DisposeAsync(){Disposed=true;ReaderRunning=false;return ValueTask.CompletedTask;}
}
public sealed class UsbTests
{
    private static UsbTransport Transport(FakeHidFactory f)=>new(f){QueryTimeout=TimeSpan.FromMilliseconds(150)};
    private static DeviceManager Manager(RealAhaKeyDevice r){var tracker=new ConfigurationChangeTracker();return new(new MockAhaKeyDevice(),tracker,NullLogger<DeviceManager>.Instance,r);}
    [Fact]public void ZeroOneAndAmbiguousCandidateSelection()
    {Assert.Equal("UsbNotFound",HidSelectionPolicy.Select([]).ErrorKey);Assert.NotNull(HidSelectionPolicy.Select([FakeHidFactory.Valid]).Candidate);Assert.Equal("UsbAmbiguous",HidSelectionPolicy.Select([FakeHidFactory.Valid,FakeHidFactory.Valid with{Path="second"}]).ErrorKey);}
    [Fact]public void WrongCollectionSizesUsageAndReportIdsAreRejected()
    {
        var c=FakeHidFactory.Valid;
        foreach(var wrong in new[]{c with{InterfaceNumber=0},c with{UsagePage=1},c with{Usage=2},c with{InputLength=64},c with{OutputLength=64},c with{InputIds=[1]},c with{OutputIds=[0,1]},c with{FeatureLength=2},c with{Vid=1},c with{InspectionError="unavailable"}})Assert.False(HidSelectionPolicy.IsValid(wrong));
        Assert.True(HidSelectionPolicy.IsValid(c with{InterfaceNumber=null,Collection=2}));
    }
    [Fact]public async Task EnumerationDoesNotOpenOrTransmit()
    {var f=new FakeHidFactory();await using var t=Transport(f);await t.DiscoverAsync();Assert.Empty(f.Sessions);}
    [Fact]public async Task AmbiguousInterfacesNeverOpen()
    {var f=new FakeHidFactory{Candidates=[FakeHidFactory.Valid,FakeHidFactory.Valid with{Path="second"}]};await using var t=Transport(f);Assert.Equal("UsbAmbiguous",(await Assert.ThrowsAsync<UsbException>(()=>t.OpenAsync())).Key);Assert.Empty(f.Sessions);}
    [Fact]public async Task QueryPairUsesSharedDecoderAndHasUsbProvenance()
    {
        var f=new FakeHidFactory();await using var r=new RealAhaKeyDevice(new(new FakeGattFactory(),GattContract.WindowsObserved),Transport(f));await r.SelectTransportAsync(PhysicalTransportKind.Usb);await r.ConnectAsync();
        Assert.True(r.Observation.IsLive);Assert.Equal(PhysicalTransportKind.Usb,r.Observation.Transport);Assert.Equal("1.0",r.Identity.Firmware);Assert.Equal(75,r.Status.Battery);Assert.Null(r.Observation.Capabilities!.Bits);Assert.NotNull(r.Observation.StatusAt);Assert.Equal(new byte[]{0,159},f.Sessions[0].Reports.Select(x=>x[5]));
        await r.DisconnectAsync();Assert.Null(r.Status.Battery);Assert.False(r.Observation.IsLive);Assert.True(f.Sessions[0].Disposed);Assert.False(f.Sessions[0].ReaderRunning);
    }
    [Theory][InlineData(false,0)][InlineData(true,64)][InlineData(true,0)]
    public async Task NativeFailureOrPartialWriteCannotPublish(bool success,int bytes)
    {var f=new FakeHidFactory{Configure=s=>s.Result=new(success,bytes,5)};await using var t=Transport(f);await t.OpenAsync();await Assert.ThrowsAsync<UsbException>(()=>t.QueryFrameAsync(0,default));Assert.False(t.Diagnostics.IsLive);Assert.True(f.Sessions[0].Disposed);Assert.Single(f.Sessions[0].Reports);}
    [Fact]public async Task TimeoutHasNoRetryAndQuarantinesOldSession()
    {
        var f=new FakeHidFactory{Configure=s=>s.Respond=false};await using var t=Transport(f);await t.OpenAsync();var old=f.Sessions[0];
        Assert.Equal("UsbTimeout",(await Assert.ThrowsAsync<UsbException>(()=>t.QueryFrameAsync(0,default))).Key);Assert.Single(old.Reports);Assert.True(old.Disposed);
        f.Configure=s=>s.Respond=false;await t.OpenAsync();var query=t.QueryFrameAsync(0,default);old.Emit("AABB004B32010002000023CCDD");Assert.False(query.IsCompletedSuccessfully);
        f.Sessions[1].Emit("AABB004B32010002000023CCDD");var result=await query;Assert.Equal(f.Sessions[1].Id,result.SessionId);
    }
    [Fact]public async Task CancellationStopsSessionAndReader()
    {var f=new FakeHidFactory{Configure=s=>s.Writing=ct=>Task.Delay(Timeout.Infinite,ct)};await using var t=Transport(f);await t.OpenAsync();using var c=new CancellationTokenSource();var query=t.QueryFrameAsync(0,c.Token);c.Cancel();await Assert.ThrowsAnyAsync<OperationCanceledException>(()=>query);await t.DisconnectAsync();await t.DisconnectAsync();Assert.True(f.Sessions[0].Disposed);}
    [Fact]public async Task OwnershipHandoffClosesOldTransportBeforeNewOpenAndNeverSyncsDraft()
    {
        var ble=new FakeGattFactory();var usb=new FakeHidFactory();await using var r=new RealAhaKeyDevice(new(ble,GattContract.WindowsObserved),Transport(usb)){Selected=new("known","AD1E",null)};
        using var m=Manager(r);using var runtime=new RealDeviceRuntime(m);await m.SelectBackendAsync(true);await runtime.StartAsync();var draft=m.Tracker.Draft;
        usb.Configure=s=>s.OnOpen=()=>Assert.True(ble.Sessions.All(b=>b.Disposed));
        await runtime.SelectTransportAsync(PhysicalTransportKind.Usb);await runtime.StartAsync();Assert.Empty(usb.Sessions);await runtime.ConnectAsync();Assert.True(r.Observation.IsLive);Assert.Same(draft,m.Tracker.Draft);Assert.Null(m.Tracker.LastDeviceRead);await m.WriteAsync();Assert.Equal("BleReadOnly",m.ErrorKey);
        await runtime.SelectTransportAsync(PhysicalTransportKind.Bluetooth);Assert.True(usb.Sessions[0].Disposed);await runtime.ConnectAsync();Assert.True(r.Diagnostics.IsLive);Assert.True(m.RealBackendSelected);await runtime.DisconnectAsync();
    }
    [Fact]public async Task UsbFailureNeverFallsBackToMockOrUsesBleBattery()
    {
        var usb=new FakeHidFactory{Candidates=[]};await using var r=new RealAhaKeyDevice(new(new FakeGattFactory(),GattContract.WindowsObserved),Transport(usb)){Selected=new("known","AD1E",null)};
        using var m=Manager(r);using var runtime=new RealDeviceRuntime(m);await m.SelectBackendAsync(true);await runtime.StartAsync();Assert.NotNull(r.Status.Battery);await runtime.SelectTransportAsync(PhysicalTransportKind.Usb);Assert.Null(r.Status.Battery);await runtime.ConnectAsync();Assert.True(m.RealBackendSelected);Assert.False(r.Identity.IsSimulation);Assert.Null(r.Status.Battery);
    }
    [Fact]public void DiagnosticsRedactPathsAndInstanceIdentity()
    {var text=UsbDiagnosticExport.Redacted(new(){Selected=FakeHidFactory.Valid,Candidates=[FakeHidFactory.Valid],Error="private-path private-instance",History=[new(DateTimeOffset.UtcNow,null,"Error","private-path")]});Assert.DoesNotContain("private-path",text);Assert.DoesNotContain("private-instance",text);}
}

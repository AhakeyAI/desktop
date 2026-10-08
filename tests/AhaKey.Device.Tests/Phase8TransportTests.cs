using System.Collections.Immutable;
using AhaKey.Core;
using AhaKey.Protocol;
using AhaKey.Device.Ble;
using AhaKey.Device.Usb;
using Microsoft.Extensions.Logging.Abstractions;
namespace AhaKey.Device.Tests;
public sealed class Phase8TransportTests
{
    private sealed class Factory:IWindowsHidSessionFactory
    {
        public Session? Current;public bool Timeout;
        public Task<IReadOnlyList<HidCandidate>> EnumerateAsync(CancellationToken ct)=>Task.FromResult<IReadOnlyList<HidCandidate>>([FakeHidFactory.Valid]);
        public IWindowsHidSession Create(Guid id)=>Current=new(id,Timeout);
    }
    private sealed class Session(Guid id,bool timeout):IWindowsHidSession
    {
        public Guid Id=>id;public bool ReaderRunning{get;private set;}private Action<HidInput>? input;public List<string> Sent=[];
        public Task OpenAsync(HidCandidate c,Action<HidInput> input,Action<Guid,Exception> fail,CancellationToken ct){this.input=input;ReaderRunning=true;return Task.CompletedTask;}
        private void Emit(string hex){var r=new byte[65];Convert.FromHexString(hex).CopyTo(r,1);input!(new(Id,DateTimeOffset.UtcNow,[..r]));}
        public Task<HidWriteResult> WriteAsync(ImmutableArray<byte> r,CancellationToken ct){Emit(r[5]==0?"AABB004B3201040200002304CCDD":"AABB9F000302010401FF0700000801CCDD");return Task.FromResult(new HidWriteResult(true,65,0));}
        public Task<HidWriteResult> WriteConfigAsync(ApprovedConfigRead query,CancellationToken ct)
        {
            query.Consume(Id);Sent.Add(Convert.ToHexString(query.Frame.AsSpan()));if(timeout)return Task.FromResult(new HidWriteResult(true,65,0));
            int total=WindowsContract32ProtocolAdapter.ResourceLength(query.Resource,query.Index),count=Math.Min(8,total-query.Offset);
            var source=new byte[total];if(query.Resource==0){source[0]=0x73;source[1]=2;source[2]=0xE0;source[3]=0x28;}else if(query.Resource==2)source[0]=35;
            Emit($"AABB9D00{query.Resource:X2}{query.Index:X2}{total:X2}{query.Offset:X2}{count:X2}"+Convert.ToHexString(source.AsSpan(query.Offset,count))+"CCDD");
            return Task.FromResult(new HidWriteResult(true,65,0));
        }
        public void Cancel(){}public ValueTask DisposeAsync(){ReaderRunning=false;return ValueTask.CompletedTask;}
    }
    [Fact] public async Task TypedReadObtainsExactlyThirteenKeySlicesWithoutConfigurationWrites()
    {
        var factory=new Factory();await using var real=new RealAhaKeyDevice(new(new FakeGattFactory(),GattContract.WindowsObserved),new(factory));
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);await manager.ConnectAsync();
        var events=new List<PhysicalCommandEvidence>();var bytes=await manager.ReadConfigAsync(0,9,events.Add);
        Assert.Equal(100,bytes.Length);Assert.Equal("Ctrl+Enter",KeyResource.Shortcut(bytes.AsSpan())!.Canonical);Assert.Equal(13,factory.Current!.Sent.Count);
        Assert.All(factory.Current.Sent,s=>Assert.StartsWith("AABB9D0009",s));Assert.Null(manager.Tracker.LastDeviceRead);
        Assert.False(manager.Operations.Journal.Last().Persistent);Assert.True(real.Observation.IsLive);
    }
    [Fact] public async Task TimedOutReadStopsAfterOneRequestAndClosesSession()
    {
        var factory=new Factory{Timeout=true};await using var real=new RealAhaKeyDevice(new(new FakeGattFactory(),GattContract.WindowsObserved),new(factory){QueryTimeout=TimeSpan.FromMilliseconds(50)});
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);await manager.ConnectAsync();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(()=>manager.ReadConfigAsync(0,9,_=>{}));
        Assert.Single(factory.Current!.Sent);Assert.False(real.Observation.IsLive);
    }
}

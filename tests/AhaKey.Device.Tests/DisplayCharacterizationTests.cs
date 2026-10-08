using System.Collections.Immutable;
using AhaKey.Device.Usb;
using AhaKey.Protocol;
namespace AhaKey.Device.Tests;
public sealed class DisplayCharacterizationTests
{
    private sealed class Factory : IWindowsHidSessionFactory
    {
        public Session? Last;public bool TimeoutLayout;public bool ShortWrite;
        public Task<IReadOnlyList<HidCandidate>> EnumerateAsync(CancellationToken ct)=>Task.FromResult<IReadOnlyList<HidCandidate>>([FakeHidFactory.Valid]);
        public IWindowsHidSession Create(Guid id)=>Last=new(id,TimeoutLayout,ShortWrite);
    }
    private sealed class Session(Guid id,bool timeoutLayout,bool shortWrite) : IWindowsHidSession
    {
        public Guid Id=>id;public bool ReaderRunning {get;private set;}public bool Closed;public List<byte> Commands=[];
        private Action<HidInput>? input;private readonly DisplayCharacterizationGuard guard=new();
        public Task OpenAsync(HidCandidate c,Action<HidInput> receive,Action<Guid,Exception> failed,CancellationToken ct){input=receive;ReaderRunning=true;return Task.CompletedTask;}
        public Task<HidWriteResult> WriteAsync(ImmutableArray<byte> report,CancellationToken ct)
        {
            guard.Consume(report.AsSpan());byte cmd=report[5];Commands.Add(cmd);
            void Emit(string frame,Guid session){var b=new byte[65];Convert.FromHexString(frame).CopyTo(b,1);input!(new(session,DateTimeOffset.UtcNow,b.ToImmutableArray()));}
            // A forged old-session response must never satisfy the current transaction.
            Emit(cmd==0?"AABB000132010002000023CCDD":$"AABB{cmd:X2}00CCDD",Guid.NewGuid());
            if(!(timeoutLayout && cmd==0x9C))Emit(cmd==0?"AABB004B32010002000023CCDD":cmd==0x83?"AABB8300000000000064002401CCDD":$"AABB{cmd:X2}00CCDD",id);
            return Task.FromResult(new HidWriteResult(true,shortWrite?64:65,0));
        }
        public void Cancel() { }
        public ValueTask DisposeAsync(){Closed=true;ReaderRunning=false;return ValueTask.CompletedTask;}
    }
    [Fact] public async Task OneShotUsesOnlyApprovedSequenceRejectsOldSessionAndCloses()
    {var f=new Factory();var runner=new DisplayCharacterization(f);var result=await runner.RunAsync(FakeHidFactory.Valid);Assert.Equal(new byte[]{0,0x9C,0x83,0x94,0},f.Last!.Commands);Assert.Equal(75,result.Queries[0].Response.Telemetry!.Battery);Assert.Equal(75,result.Queries[4].Response.Telemetry!.Battery);Assert.Equal(DisplayResponseKind.EMPTY_SUCCESS_ACK,result.Queries[1].Response.Classification);Assert.True(result.ReaderStopped&&result.TeardownCompleted&&f.Last.Closed);Assert.All(result.Queries,q=>Assert.Single(q.InputReports));await Assert.ThrowsAsync<InvalidOperationException>(()=>runner.RunAsync(FakeHidFactory.Valid));}
    [Fact] public async Task TimeoutNeverRetriesAndFinalHealthStillUsesRemainingSlot()
    {var f=new Factory{TimeoutLayout=true};var r=await new DisplayCharacterization(f){Timeout=TimeSpan.FromMilliseconds(30)}.RunAsync(FakeHidFactory.Valid);Assert.Equal(DisplayResponseKind.TIMEOUT,r.Queries[1].Response.Classification);Assert.Equal(1,f.Last!.Commands.Count(x=>x==0x9C));Assert.Equal(5,r.Queries.Count);Assert.True(r.ReaderStopped&&r.TeardownCompleted);}
    [Fact] public async Task PartialWriteStopsSequenceAndAlwaysReleasesReader()
    {var f=new Factory{ShortWrite=true};var r=await new DisplayCharacterization(f).RunAsync(FakeHidFactory.Valid);Assert.Single(r.Queries);Assert.Null(r.Queries[0].Response.Telemetry);Assert.True(f.Last!.Closed&&r.ReaderStopped);}
}

using System.Collections.Immutable;
using AhaKey.Core;
using AhaKey.Protocol;
using AhaKey.Device.Ble;
using AhaKey.Device.Usb;
using Microsoft.Extensions.Logging.Abstractions;
namespace AhaKey.Device.Tests;
public sealed class PhysicalControlTests
{
    private sealed class Factory : IWindowsHidSessionFactory
    {
        public Session? Current; public int FailAt;
        public Task<IReadOnlyList<HidCandidate>> EnumerateAsync(CancellationToken ct)=>Task.FromResult<IReadOnlyList<HidCandidate>>([FakeHidFactory.Valid]);
        public IWindowsHidSession Create(Guid id)=>Current=new(id,FailAt);
    }
    private sealed class Session(Guid id,int failAt) : IWindowsHidSession
    {
        private Action<HidInput>? receive;
        public Guid Id=>id;public bool ReaderRunning{get;private set;} public List<ImmutableArray<byte>> Controls=[];
        public TaskCompletionSource? QueryEntered,QueryRelease;
        public Task OpenAsync(HidCandidate c,Action<HidInput> input,Action<Guid,Exception> failed,CancellationToken ct){receive=input;ReaderRunning=true;return Task.CompletedTask;}
        private void Emit(string hex){var report=new byte[65];Convert.FromHexString(hex).CopyTo(report,1);receive!(new(Id,DateTimeOffset.UtcNow,[..report]));}
        public async Task<HidWriteResult> WriteAsync(ImmutableArray<byte> r,CancellationToken ct){Assert.True(UsbReportCodec.IsAllowedReport(r.AsSpan()));if(QueryRelease is {} release){QueryEntered!.TrySetResult();await release.Task.WaitAsync(ct);}Emit(r[5]==0?"AABB004B32010002000023CCDD":"AABB9F00CCDD");return new HidWriteResult(true,65,0);}
        public Task<HidWriteResult> WriteControlAsync(ApprovedControl control,CancellationToken ct)
        {control.Consume(Id,control.Command.Frame.AsSpan());Controls.Add(control.Command.Frame);Emit($"AABB{control.Command.Opcode:X2}{(Controls.Count==failAt?1:0):X2}CCDD");return Task.FromResult(new HidWriteResult(true,65,0));}
        public void Cancel(){} public ValueTask DisposeAsync(){ReaderRunning=false;return ValueTask.CompletedTask;}
    }
    private static KeyWritePlan Plan(){ShortcutGesture.TryParse("Ctrl+Enter",out var g);return KeyWritePlan.Create(HardwareProfileId.Codex,PhysicalKey.K2,new(g!,"Send"));}
    [Theory][InlineData(true)][InlineData(false)]
    public async Task ApprovalQueryDoesNotFailFeedbackAndOptInIsRecheckedAfterWaiting(bool remainsEnabled)
    {
        var usb=new Factory();await using var real=new RealAhaKeyDevice(new(new FakeGattFactory(),GattContract.WindowsObserved),new(usb));
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);await manager.ConnectAsync();
        var native=usb.Current!;native.QueryEntered=new(TaskCreationOptions.RunContinuationsAsynchronously);native.QueryRelease=new(TaskCreationOptions.RunContinuationsAsynchronously);
        var query=manager.RefreshApprovalStatusAsync(default);await native.QueryEntered.Task;
        var service=new PhysicalFeedbackService(manager);var log=new List<PhysicalCommandEvidence>();bool enabled=true;
        var input=new FeedbackInput(real.Observation.SessionId!.Value,HardwareProfileId.Codex,"Codex",IdeEventState.PreToolUse,"CodexPreToolUse");
        var feedback=service.HandleAsync(input,true,CodexFeedbackMapping.Simple,new HashSet<byte>{0,1},log.Add,stillEnabled:()=>enabled);
        Assert.False(feedback.IsCompleted);Assert.Empty(native.Controls);
        enabled=remainsEnabled;native.QueryRelease.SetResult();await query;
        Assert.Equal(remainsEnabled,await feedback);Assert.Equal(remainsEnabled?1:0,native.Controls.Count);
        if(remainsEnabled)Assert.Equal("AABB9101CCDD",log.Single().Tx);
    }
    [Theory][InlineData(0,3)][InlineData(1,1)][InlineData(2,2)][InlineData(3,3)]
    public async Task SaveOnlyFollowsSuccessfulMinimalCommandsAndNoRetry(int failAt,int expected)
    {
        var factory=new Factory{FailAt=failAt};var ble=new FakeGattFactory();
        await using var real=new RealAhaKeyDevice(new(ble,GattContract.WindowsObserved),new(factory));
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);await manager.ConnectAsync();
        var approved=ApprovedControlPlan.Key(real.Status.SessionId!.Value,"offline explicit approval",Plan());var ledger=new List<PhysicalCommandEvidence>();
        if(failAt==0)await manager.ExecuteControlsAsync(approved,ledger.Add);else await Assert.ThrowsAsync<PhysicalControlException>(()=>manager.ExecuteControlsAsync(approved,ledger.Add));
        Assert.Equal(expected,factory.Current!.Controls.Count);Assert.Equal(expected,ledger.Count);Assert.Empty(ble.Sessions);
        if(failAt>0){Assert.NotNull(ledger[^1].Error);Assert.False(real.Observation.IsLive);}
        else {Assert.All(ledger,e=>Assert.Null(e.Error));await Assert.ThrowsAsync<InvalidOperationException>(()=>manager.ExecuteControlsAsync(approved,ledger.Add));}
        Assert.Null(manager.Tracker.LastDeviceRead);
    }
    [Fact]public void ExactSessionAndOneShotApprovalAreRequired()
    {
        var id=Guid.NewGuid();var plan=ApprovedControlPlan.Key(id,"approved",Plan());Assert.Throws<InvalidOperationException>(()=>plan.Begin(Guid.NewGuid()));
        var commands=plan.Begin(id);Assert.Throws<InvalidOperationException>(()=>plan.Begin(id));
        var first=commands[0];first.Consume(id,first.Command.Frame.AsSpan());Assert.Throws<InvalidOperationException>(()=>first.Consume(id,first.Command.Frame.AsSpan()));
        Assert.Throws<ArgumentException>(()=>ApprovedControlPlan.Key(id,"approved",Plan() with{Commands=[LegacyControlCommand.Effect(1),LegacyControlCommand.SaveKeys()]}));
    }
    [Fact]public async Task FeedbackUsesOnlyActiveBleOnceAndRequiresMatchingPhysicalProfile()
    {
        var ble=new FakeGattFactory();var usb=new Factory();await using var real=new RealAhaKeyDevice(new(ble,GattContract.WindowsObserved),new(usb)){Selected=new("fake","Fake",null)};
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        await manager.SelectBackendAsync(true);await manager.ConnectAsync();var service=new PhysicalFeedbackService(manager);var ledger=new List<PhysicalCommandEvidence>();
        var ev=new FeedbackInput(real.Observation.SessionId!.Value,HardwareProfileId.Codex,"Codex",IdeEventState.PreToolUse,"CodexPreToolUse");var map=new Dictionary<IdeEventState,byte>{{ev.Event,1}};var accepted=new HashSet<byte>{0,1};
        Assert.False(await service.HandleAsync(ev,false,map,accepted,ledger.Add));
        Assert.False(await service.HandleAsync(ev with{Profile=HardwareProfileId.Claude},true,map,accepted,ledger.Add));
        Assert.True(await service.HandleAsync(ev,true,map,accepted,ledger.Add));Assert.False(await service.HandleAsync(ev,true,map,accepted,ledger.Add));
        Assert.Single(ble.Sessions.Single().Controls);Assert.Null(usb.Current);Assert.Single(ledger);Assert.Equal(PhysicalTransportKind.Bluetooth,ledger[0].Transport);
    }
    [Fact]public async Task BleNativeFailureCannotBeSuccessDespiteEarlyAck()
    {
        var ble=new FakeGattFactory();await using var real=new RealAhaKeyDevice(new(ble,GattContract.WindowsObserved)){Selected=new("fake","Fake",null)};
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);await manager.SelectBackendAsync(true);await manager.ConnectAsync();
        ble.Sessions.Single().WriteResult=new(GattResultStatus.AccessDenied);var ledger=new List<PhysicalCommandEvidence>();
        await Assert.ThrowsAsync<PhysicalControlException>(()=>manager.ExecuteControlsAsync(ApprovedControlPlan.Key(real.Observation.SessionId!.Value,"offline",Plan()),ledger.Add));
        Assert.Single(ledger);Assert.Single(ble.Sessions.Single().Controls);Assert.False(real.Observation.IsLive);
    }
    [Fact]public async Task QueuedNeutralRechecksOptInAndCanFollowBusyEffect()
    {
        var usb=new Factory();await using var real=new RealAhaKeyDevice(new(new FakeGattFactory(),GattContract.WindowsObserved),new(usb));
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);await manager.ConnectAsync();
        var service=new PhysicalFeedbackService(manager);var log=new List<PhysicalCommandEvidence>();
        var ev=new FeedbackInput(real.Observation.SessionId!.Value,HardwareProfileId.Codex,"Codex",IdeEventState.UserPromptSubmit,"native");
        var map=new Dictionary<IdeEventState,byte>{{IdeEventState.UserPromptSubmit,1},{IdeEventState.Stop,0}};var accepted=new HashSet<byte>{0,1};
        var entered=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);var release=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var first=Task.Run(()=>service.HandleAsync(ev,true,map,accepted,log.Add,beforeSend:(_,_)=>{entered.SetResult();release.Task.GetAwaiter().GetResult();}));
        await entered.Task;var neutral=service.HandleAsync(ev with{Event=IdeEventState.Stop},true,map,accepted,log.Add,stillEnabled:()=>true);
        Assert.False(neutral.IsCompleted);release.SetResult();Assert.True(await first);Assert.True(await neutral);
        Assert.Equal(new[]{"AABB9101CCDD","AABB9100CCDD"},usb.Current!.Controls.Select(c=>Convert.ToHexString(c.AsSpan())));
        Assert.False(await service.HandleAsync(ev with{Event=IdeEventState.Stop},true,map,accepted,log.Add,stillEnabled:()=>false));
        Assert.Equal(2,usb.Current.Controls.Count);
    }
    [Fact]public async Task FeedbackOffProducesZeroOutputAliasesDeduplicateAndNeutralFollows()
    {
        var usb=new Factory();await using var real=new RealAhaKeyDevice(new(new FakeGattFactory(),GattContract.WindowsObserved),new(usb));
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);await manager.ConnectAsync();
        var service=new PhysicalFeedbackService(manager);var log=new List<PhysicalCommandEvidence>();var results=new List<FeedbackDecision>();
        var ev=new FeedbackInput(real.Observation.SessionId!.Value,HardwareProfileId.Codex,"Codex",IdeEventState.UserPromptSubmit,"legacy");
        var map=new Dictionary<IdeEventState,byte>{{IdeEventState.UserPromptSubmit,1},{IdeEventState.Stop,0}};var accepted=new HashSet<byte>{0,1};
        Assert.False(await service.HandleAsync(ev,false,map,accepted,log.Add,report:results.Add));Assert.Empty(usb.Current!.Controls);
        Assert.True(await service.HandleAsync(ev,true,map,accepted,log.Add,report:results.Add));
        Assert.False(await service.HandleAsync(ev with{NativeEvent="studio"},true,map,accepted,log.Add,report:results.Add));
        Assert.True(await service.HandleAsync(ev with{Event=IdeEventState.Stop},true,map,accepted,log.Add,report:results.Add));
        Assert.Equal(new[]{"AABB9101CCDD","AABB9100CCDD"},usb.Current.Controls.Select(c=>Convert.ToHexString(c.AsSpan())));
        Assert.Equal(4,service.Received);Assert.Equal(1,service.SuppressedDuplicates);Assert.Equal(2,service.PhysicalOperations);Assert.Equal(2,service.SuccessfulOperations);
        Assert.Equal(FeedbackDisposition.Disabled,results[0].Disposition);Assert.Equal(FeedbackDisposition.Duplicate,results[2].Disposition);
    }
}

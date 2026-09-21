using System.Collections.Immutable;
using AhaKey.Protocol;
using AhaKey.Device.Ble;
using AhaKey.Device.Usb;
using Microsoft.Extensions.Logging.Abstractions;
namespace AhaKey.Device.Tests;
public class StaticDisplayUploadTests
{
    [Theory]
    [InlineData(true,true,true,2,9,true)]
    [InlineData(false,true,true,2,9,false)]
    [InlineData(true,false,true,2,9,false)]
    [InlineData(true,true,false,2,9,false)]
    [InlineData(true,true,true,1,9,false)]
    [InlineData(true,true,true,2,8,false)]
    public void AcceptanceRequiresProtocolMetadataVisualAndExactScope(bool protocol,bool metadata,bool visual,int profile,int slot,bool expected)
    {
        var proof=new StaticDisplayAcceptance(Guid.NewGuid(),profile,slot,new string('A',64),protocol,metadata,visual);
        Assert.Equal(expected,proof.PromotesCapability);
        Assert.False((proof with{Session=Guid.Empty}).PromotesCapability);
        Assert.False((proof with{FrameSha256="unknown"}).PromotesCapability);
    }
    private sealed class Factory : IWindowsHidSessionFactory
    {
        public Session? Current;public bool FailFirstData,WrongBinding;public Windows32DisplayUploadPlan? Modern;
        public Task<IReadOnlyList<HidCandidate>> EnumerateAsync(CancellationToken ct)=>Task.FromResult<IReadOnlyList<HidCandidate>>([FakeHidFactory.Valid]);
        public IWindowsHidSession Create(Guid id)=>Current=new(id,FailFirstData,WrongBinding,Modern);
    }
    private sealed class Session(Guid id,bool failData,bool wrongBinding,Windows32DisplayUploadPlan? modern):IWindowsHidSession
    {
        public Guid Id=>id;public bool ReaderRunning{get;private set;}private Action<HidInput>? input;private int remaining;
        public List<ImmutableArray<byte>> Sent=[];
        public Task OpenAsync(HidCandidate candidate,Action<HidInput> input,Action<Guid,Exception> failed,CancellationToken ct){this.input=input;ReaderRunning=true;return Task.CompletedTask;}
        void Emit(string hex){var r=new byte[65];Convert.FromHexString(hex).CopyTo(r,1);input!(new(Id,DateTimeOffset.UtcNow,[..r]));}
        public Task<HidWriteResult> WriteAsync(ImmutableArray<byte> r,CancellationToken ct)
        {Assert.True(UsbReportCodec.IsAllowedReport(r.AsSpan()));Emit(modern is null?(r[5]==0?"AABB004B32010002000023CCDD":"AABB9F00CCDD"):(r[5]==0?"AABB004B3201040200002304CCDD":"AABB9F000302010401FF0700000801CCDD"));return Task.FromResult(new HidWriteResult(true,65,0));}
        public Task<HidWriteResult> WriteDisplayAsync(ApprovedDisplayReport permit,CancellationToken ct)
        {
            permit.Consume(Id);var r=permit.Report;Sent.Add(r);
            if(r[1]==0xA1)
            {
                byte opcode=r[5];if(opcode==0x80)remaining=r[7]|r[8]<<8;
                if(modern is not null && opcode is 0x83 or 0x94)
                {
                    var binding=modern.Transfer.Binding;
                    Emit($"AABB{opcode:X2}00"+Convert.ToHexString(binding.AsSpan(3,binding.Length-5))+"2401CCDD");
                }
                else Emit(opcode==0x83?(wrongBinding?"AABB8300020800010064002401CCDD":"AABB8300020900010064002401CCDD"):$"AABB{opcode:X2}00CCDD");
            }
            else {if(failData)return Task.FromResult(new HidWriteResult(false,0,5));remaining-=r[2];Assert.True(remaining>=0);if(remaining==0)Emit("AABB8100CCDD");}
            return Task.FromResult(new HidWriteResult(true,65,0));
        }
        public void Cancel(){}public ValueTask DisposeAsync(){ReaderRunning=false;return ValueTask.CompletedTask;}
    }
    [Fact] public void DisplayPermissionBindsHashSessionOrderAndSingleUse()
    {
        var plan=StaticDisplayPlan.Create(StaticDisplayPlan.ExpectedBinding,[new byte[25600]]);var id=Guid.NewGuid();
        Assert.Throws<ArgumentException>(()=>new ApprovedDisplayUpload(id,"",plan.Sha256,plan));Assert.Throws<ArgumentException>(()=>new ApprovedDisplayUpload(id,"approve","wrong",plan));
        var approval=new ApprovedDisplayUpload(id,"explicit destructive asset approval",plan.Sha256,plan);
        Assert.Throws<InvalidOperationException>(()=>approval.Begin(Guid.NewGuid()));var reports=approval.Begin(id);
        Assert.Throws<InvalidOperationException>(()=>approval.Begin(id));Assert.Throws<InvalidOperationException>(()=>reports[1].Consume(id));
        reports[0].Consume(id);Assert.Throws<InvalidOperationException>(()=>reports[0].Consume(id));
    }
    [Theory][InlineData(false,false,436)][InlineData(true,false,3)][InlineData(false,true,1)]
    public async Task TransactionRequiresPreflightAndBlockAcksBeforeBindingAndSave(bool failData,bool wrongBinding,int expected)
    {
        var factory=new Factory{FailFirstData=failData,WrongBinding=wrongBinding};await using var real=new RealAhaKeyDevice(new(new FakeGattFactory(),GattContract.WindowsObserved),new(factory));
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);await manager.ConnectAsync();
        var plan=StaticDisplayPlan.Create(StaticDisplayPlan.ExpectedBinding,[new byte[25600]]);var permit=new ApprovedDisplayUpload(real.Observation.SessionId!.Value,"offline only",plan.Sha256,plan);
        var log=new List<DisplayTransferEvidence>();var responses=new List<DisplayResponseEvidence>();
        if(failData||wrongBinding){await Assert.ThrowsAnyAsync<Exception>(()=>manager.UploadDisplayAsync(permit,log.Add,responses.Add));Assert.False(real.Observation.IsLive);}
        else {await manager.UploadDisplayAsync(permit,log.Add,responses.Add);Assert.Equal(18,responses.Count);Assert.Equal(425,factory.Current!.Sent.Count(r=>r[1]==0xA2));}
        var operation=manager.Operations.Journal.Last(x=>x.Operation=="Display upload");
        Assert.Equal(failData||wrongBinding?OperationOutcome.OutcomeUncertain:OperationOutcome.Completed,operation.Outcome);
        Assert.Equal(!(failData||wrongBinding),operation.SaveConfirmed);Assert.Equal(!(failData||wrongBinding),operation.BindingChanged);
        if(wrongBinding){Assert.Equal(0,operation.ConfirmedSteps);Assert.Single(responses);Assert.StartsWith("REJECTED",responses[0].Stage);}
        if(!failData&&!wrongBinding)Assert.Contains("0x045000",operation.LastConfirmedFlashBlock);
        Assert.Equal(expected,factory.Current!.Sent.Count);
        if(failData||wrongBinding)Assert.DoesNotContain(factory.Current.Sent,r=>r[1]==0xA1 && r[5] is 0x82 or 4);
        Assert.Null(manager.Tracker.LastDeviceRead);
    }
    [Theory]
    [InlineData(AhaKey.Core.DisplayState.Default)]
    [InlineData(AhaKey.Core.DisplayState.Working)]
    public async Task ModernAnimationTransfersTwoFramesAndVerifiesCorrectMetadata(AhaKey.Core.DisplayState state)
    {
        var plan=Windows32DisplayUploadPlan.Create(AhaKey.Core.HardwareProfileId.Codex,state,[new byte[25600],Enumerable.Repeat((byte)0xA5,25600).ToArray()],569);
        var factory=new Factory{Modern=plan};await using var real=new RealAhaKeyDevice(new(new FakeGattFactory(),GattContract.WindowsObserved),new(factory));
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);await manager.ConnectAsync();
        var responses=new List<DisplayResponseEvidence>();
        await manager.UploadDisplayAsync(new(real.Observation.SessionId!.Value,"offline animation test",plan.Sha256,plan),_=>{},responses.Add);
        Assert.Equal(850,factory.Current!.Sent.Count(r=>r[1]==0xA2));
        Assert.Equal(14,responses.Count(r=>r.Stage.StartsWith("81 sector")));
        Assert.True(plan.MatchesBinding(Convert.FromHexString(responses[^1].Frame),true));
        var operation=manager.Operations.Journal.Last(x=>x.Operation=="Display upload");
        Assert.True(operation.SaveConfirmed);Assert.True(operation.BindingChanged);Assert.Equal(OperationOutcome.Completed,operation.Outcome);
    }
}

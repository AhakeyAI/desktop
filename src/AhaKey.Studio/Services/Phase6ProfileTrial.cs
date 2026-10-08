using System.IO;
using System.Text.Json;
using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Device.Ble;
using AhaKey.Device.Usb;
using AhaKey.Services;
using Microsoft.Extensions.Logging.Abstractions;
namespace AhaKey.Studio.Services;

// Sole new Phase 6 protocol experiment. Explicit approval file, one-shot marker, no save/retry.
public static class Phase6ProfileTrial
{
    public sealed record Approval(string Device,int Initial,int Test,int Restore,bool NoSave,string UserApproval);
    public static async Task RunAsync(string output,string approvalPath)
    {
        Directory.CreateDirectory(output);
        void Save(string name,object value)=>File.WriteAllText(Path.Combine(output,name),JsonSerializer.Serialize(value,new JsonSerializerOptions{WriteIndented=true}));
        var a=JsonSerializer.Deserialize<Approval>(File.ReadAllText(approvalPath))??throw new InvalidOperationException("Approval absent.");
        if(a.Device!="AD1E" || a.Initial!=2 || a.Test!=1 || a.Restore!=2 || !a.NoSave || string.IsNullOrWhiteSpace(a.UserApproval))throw new InvalidOperationException("Exact 2-1-2 approval required.");
        var settings=new SettingsStore();using var owner=new SingleInstanceOwner(settings.Root);
        if(!owner.IsPrimary)throw new InvalidOperationException("Close Studio before the approved profile test.");
        var acceptancePath=Path.Combine(settings.Root,"physical-controls-acceptance.json");
        var accepted=JsonSerializer.Deserialize<ControlAcceptance>(File.ReadAllText(acceptancePath))??throw new InvalidOperationException("Accepted device absent.");
        var factory=new WindowsHidSessionFactory();var candidate=HidSelectionPolicy.Select(await factory.EnumerateAsync(default)).Candidate??throw new InvalidOperationException("Connect the accepted AD1E by USB.");
        var hash=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes("Usb:"+candidate.Path)));
        if(hash!=accepted.DeviceHash)throw new InvalidOperationException("Device identity differs.");
        await using var real=new RealAhaKeyDevice(new(new WindowsGattSessionFactory(),GattContract.WindowsObserved),new(factory));
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);
        var ledger=new List<PhysicalCommandEvidence>();ProfileSwitchAcceptance? proof=null;bool attempted=false;
        void Record(PhysicalCommandEvidence value){ledger.Add(value);Save("commands.json",ledger);}
        try
        {
            await manager.ConnectAsync();
            if(real.Observation is not {IsLive:true,SessionId:{} session,Status:{WorkMode:2}} || real.Identity.Firmware!="1.0")throw new InvalidOperationException("Fresh initial USB mode 2 / firmware 1.0 required.");
            Save("baseline.json",real.Usb!.Diagnostics.LastStatusQuery!);
            proof=new(session,true,false,false,false,false);
            using(var marker=new FileStream(Path.Combine(settings.Root,"phase6-profile-trial-attempted.lock"),FileMode.CreateNew,FileAccess.Write,FileShare.None))
            {JsonSerializer.Serialize(marker,a);marker.Flush(true);}
            Save("approval.json",a);attempted=true;
            try
            {
                await manager.ExecuteControlsAsync(ApprovedControlPlan.WorkProfile(session,a.UserApproval,HardwareProfileId.Cursor),Record);
                proof=proof with{SwitchAck=true};
                var status=await manager.RefreshApprovalStatusAsync(default);Save("mode1-query.json",real.Usb.Diagnostics.LastStatusQuery!);
                proof=proof with{Observed1=status is {IsLive:true,Status:{WorkMode:1}} && status.SessionId==session};
            }
            finally
            {
                if(attempted && real.Observation is {IsLive:true,SessionId:{} live} && live==session)
                {
                    await manager.ExecuteControlsAsync(ApprovedControlPlan.WorkProfile(session,a.UserApproval+"; restore 2",HardwareProfileId.Codex),Record);
                    proof=proof with{RestoreAck=true};
                    var status=await manager.RefreshApprovalStatusAsync(default);Save("mode2-query.json",real.Usb.Diagnostics.LastStatusQuery!);
                    proof=proof with{Observed2=status is {IsLive:true,Status:{WorkMode:2}} && status.SessionId==session};
                }
            }
            if(proof.Accepted)
            {
                File.Copy(acceptancePath,Path.Combine(output,"acceptance-before.private.json"),false);
                File.WriteAllText(acceptancePath,JsonSerializer.Serialize(accepted with{ProfileSwitch=proof},new JsonSerializerOptions{WriteIndented=true}));
            }
        }
        finally
        {
            if(proof is not null)Save("result.json",proof);
            await manager.DisconnectAsync();Save("closed.json",new{At=DateTimeOffset.UtcNow,Disconnected=!real.Observation.IsLive,ReaderStopped=!real.Usb!.Diagnostics.ReaderRunning,Writes=ledger.Count});
        }
    }
}

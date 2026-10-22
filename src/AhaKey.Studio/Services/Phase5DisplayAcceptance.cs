using System.IO;
using System.Text.Json;
using AhaKey.Device;
using AhaKey.Device.Ble;
using AhaKey.Device.Usb;
using AhaKey.Protocol;
using AhaKey.Services;
using Microsoft.Extensions.Logging.Abstractions;
namespace AhaKey.Studio.Services;

public sealed record StaticDisplayApproval(string Device,string Transport,int Profile,string State,int Slot,string FrameSha256,bool PixelLossApproved,string UserApproval);
public static class Phase5DisplayAcceptance
{
    public static async Task RunAsync(string output,string approvalPath,string framePath)
    {
        output=Path.GetFullPath(output);Directory.CreateDirectory(output);
        void Save(string name,object value)=>File.WriteAllText(Path.Combine(output,name),JsonSerializer.Serialize(value,new JsonSerializerOptions{WriteIndented=true}));
        var approval=JsonSerializer.Deserialize<StaticDisplayApproval>(File.ReadAllText(approvalPath))??throw new InvalidOperationException("Missing Display approval.");
        var plan=StaticDisplayPlan.Create(StaticDisplayPlan.ExpectedBinding,[File.ReadAllBytes(framePath)]);
        if(approval.Device!="AD1E" || approval.Transport!="USB" || approval.Profile!=2 || approval.State!="Default" || approval.Slot!=9 ||
            approval.FrameSha256!=plan.Sha256 || !approval.PixelLossApproved || string.IsNullOrWhiteSpace(approval.UserApproval))throw new InvalidOperationException("Approval differs from exact Display target/frame.");
        var settings=new SettingsStore();using var owner=new SingleInstanceOwner(settings.Root);
        if(!owner.IsPrimary)throw new InvalidOperationException("Close Studio before the Display experiment.");
        var acceptance=JsonSerializer.Deserialize<ControlAcceptance>(File.ReadAllText(Path.Combine(settings.Root,"physical-controls-acceptance.json")))??throw new InvalidOperationException("Missing accepted unit.");
        var factory=new WindowsHidSessionFactory();var candidate=HidSelectionPolicy.Select(await factory.EnumerateAsync(default)).Candidate??throw new InvalidOperationException("No unique validated USB device.");
        var hash=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes("Usb:"+candidate.Path)));
        if(hash!=acceptance.DeviceHash)throw new InvalidOperationException("USB identity differs; nothing transmitted.");
        await using var real=new RealAhaKeyDevice(new(new WindowsGattSessionFactory(),GattContract.WindowsObserved),new(factory));
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);
        var writes=new Dictionary<int,DisplayTransferEvidence>();var responses=new List<DisplayResponseEvidence>();
        try
        {
            await manager.ConnectAsync();
            if(real.Observation is not {IsLive:true,SessionId:{} session,Status:{WorkMode:2}} || real.Identity.Firmware!=acceptance.Firmware || PhysicalControlRuntime.DeviceHash(real)!=acceptance.DeviceHash)
                throw new InvalidOperationException("Expected accepted AD1E USB firmware and active profile 2.");
            Save("baseline.json",new{Session=session,real.Identity.Firmware,Status=real.Usb!.Diagnostics.LastStatusQuery});
            using(var marker=new FileStream(Path.Combine(settings.Root,"phase5-first-static-display-attempted.lock"),FileMode.CreateNew,FileAccess.Write,FileShare.None))
            {JsonSerializer.Serialize(marker,new{At=DateTimeOffset.UtcNow,Approval=approval});marker.Flush(true);}
            Save("approved-operation.json",approval);File.WriteAllBytes(Path.Combine(output,"frame.rgb565"),plan.Frame.ToArray());
            await manager.UploadDisplayAsync(new(session,approval.UserApproval,approval.FrameSha256,plan),
                e=>{writes[e.Sequence]=e;File.AppendAllText(Path.Combine(output,"native-write-events.jsonl"),JsonSerializer.Serialize(e)+Environment.NewLine);},
                e=>{responses.Add(e);Save("response-ledger.json",responses);});
            Save("transaction-result.json",new{At=DateTimeOffset.UtcNow,Session=session,ProtocolAccepted=true,MetadataMatches=true,VisualAcceptance=false,plan.Sha256,Profile=2,State="Default",Slot=9,FrameCount=1});
        }
        finally
        {
            Save("native-write-ledger.json",writes.Values.OrderBy(x=>x.Sequence));await manager.DisconnectAsync();
            Save("closed.json",new{At=DateTimeOffset.UtcNow,Disconnected=!real.Observation.IsLive,ReaderStopped=!real.Usb!.Diagnostics.ReaderRunning,Reports=writes.Count});
        }
    }
}

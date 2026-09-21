using System.IO;
using System.Text.Json;
using System.Security.Cryptography;
using System.Text;
using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Device.Ble;
using AhaKey.Device.Usb;
using AhaKey.Protocol;
using AhaKey.Services;
using Microsoft.Extensions.Logging.Abstractions;
namespace AhaKey.Studio.Services;
public static class Phase9DisplayAcceptance
{
    public static async Task RunAsync(string output)
    {
        Directory.CreateDirectory(output);var settings=new SettingsStore();using var owner=new SingleInstanceOwner(settings.Root);
        if(!owner.IsPrimary)throw new InvalidOperationException("Close Studio before USB regression.");
        var project=JsonSerializer.Deserialize<LocalDeviceProject>(File.ReadAllText(Path.Combine(settings.Root,"project.v1.json")))??throw new InvalidOperationException("Project missing.");
        var asset=project.DisplayProjects.Single(x=>x.Name=="codex_robot"&&x.Profile==HardwareProfileId.Codex&&x.State==DisplayState.Default);
        var bytes=Convert.FromBase64String(project.EmbeddedAssets[asset.AssetId]);
        if(Convert.ToHexString(SHA256.HashData(bytes))!=asset.AssetId)throw new InvalidOperationException("Asset hash mismatch.");
        var file=Path.Combine(output,"regression-source.gif");File.WriteAllBytes(file,bytes);
        var prepared=DisplayImagePreparation.Load(file,8,Enum.Parse<DisplayFitMode>(asset.Fit),asset.Background);
        var plan=Windows32DisplayUploadPlan.Create(asset.Profile,asset.State,asset.FrameOrder.Select(i=>prepared.Frames[i]).ToArray(),asset.UniformIntervalMs);
        if(plan.Sha256!="6B68E42D0BCFE8BFD30DE07F639E719B7B51D62E4889B41A1FD7C163E18554DF"||plan.Transfer.FrameCount!=8||plan.Transfer.IntervalMs!=569)throw new InvalidOperationException("Plan differs from the user's previously accepted GIF; nothing sent.");
        var receipt=JsonSerializer.Deserialize<ControlAcceptance>(File.ReadAllText(Path.Combine(settings.Root,"physical-controls-acceptance.json")))??throw new InvalidOperationException("Accepted unit missing.");
        var factory=new WindowsHidSessionFactory();var candidate=HidSelectionPolicy.Select(await factory.EnumerateAsync(default)).Candidate??throw new InvalidOperationException("No unique USB target.");
        if(Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes("Usb:"+candidate.Path)))!=receipt.DeviceHash)throw new InvalidOperationException("Different physical USB unit.");
        await using var real=new RealAhaKeyDevice(new(new WindowsGattSessionFactory(),GattContract.WindowsObserved),new(factory));
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        void Save(string name,object value)=>File.WriteAllText(Path.Combine(output,name),JsonSerializer.Serialize(value,new JsonSerializerOptions{WriteIndented=true}));
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);
        try
        {
            await manager.ConnectAsync();
            if(real.FirmwareIdentity is not {ReportedVersion:"1.4.8",ReportedProtocol:"3.2",ReportedModel:1} || real.Observation is not {IsLive:true,SessionId:{} session})throw new InvalidOperationException("Known live 1.4.8 / 3.2 target required.");
            Save("baseline.json",new{Unit="AD1E",Transport="USB",Identity=real.FirmwareIdentity,Status=real.Usb!.Diagnostics.LastStatusQuery});
            Save("plan.json",new{plan.Sha256,plan.Allocation,plan.Transfer.FrameCount,plan.Transfer.IntervalMs,Source="Same previously accepted user GIF",FirmwareWrites=false});
            using(var once=new FileStream(Path.Combine(output,"attempted.lock"),FileMode.CreateNew,FileAccess.Write,FileShare.None)){once.Flush(true);}
            await manager.UploadDisplayAsync(new(session,"Phase 9 requested USB GIF regression: repeat exact accepted user GIF, same allocation and timing; no retries",plan.Sha256,plan),
                e=>File.AppendAllText(Path.Combine(output,"writes.jsonl"),JsonSerializer.Serialize(e)+Environment.NewLine),
                e=>File.AppendAllText(Path.Combine(output,"responses.jsonl"),JsonSerializer.Serialize(e)+Environment.NewLine));
            await manager.ReadAsync();Save("completed.json",new{At=DateTimeOffset.UtcNow,MetadataConfirmed=true,VisualConfirmationPending=true,Status=real.Usb.Diagnostics.LastStatusQuery});
        }
        finally{await manager.DisconnectAsync();Save("closed.json",new{Disconnected=!real.Observation.IsLive,Retry=false});}
    }
}

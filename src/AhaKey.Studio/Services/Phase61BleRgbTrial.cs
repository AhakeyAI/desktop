using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Device.Ble;
using AhaKey.Services;
using Microsoft.Extensions.Logging.Abstractions;
namespace AhaKey.Studio.Services;
public static class Phase61BleRgbTrial
{
    public sealed record Approval(string Device,string DeviceHash,string Effect,string Neutral,bool ObserverReady,string UserApproval);
    public sealed record Visual(bool EffectObserved,bool NeutralObserved,string UserStatement);
    private static readonly JsonSerializerOptions Json=new(){WriteIndented=true};
    public static async Task RunAsync(string output,string approvalFile)
    {
        Directory.CreateDirectory(output);
        void Save(string name,object data)=>File.WriteAllText(Path.Combine(output,name),JsonSerializer.Serialize(data,Json));
        var a=JsonSerializer.Deserialize<Approval>(File.ReadAllText(approvalFile))??throw new InvalidOperationException("Explicit approval required.");
        var store=new SettingsStore();var settings=store.Load();
        var hash=Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes("Bluetooth:"+settings.BleDeviceId)));
        if(a.Device!="AD1E" || settings.BleDeviceName!="AhaKey AD1E" || string.IsNullOrEmpty(settings.BleDeviceId) || a.DeviceHash!=hash || a.Effect!="AABB9101CCDD" || a.Neutral!="AABB9100CCDD" || !a.ObserverReady || string.IsNullOrWhiteSpace(a.UserApproval))throw new InvalidOperationException("Approval does not match the saved AD1E BLE route.");
        using var owner=new SingleInstanceOwner(store.Root);if(!owner.IsPrimary)throw new InvalidOperationException("Close normal Studio first.");
        await using var real=new RealAhaKeyDevice(new(new WindowsGattSessionFactory(),GattContract.WindowsObserved));
        real.Selected=new(settings.BleDeviceId,settings.BleDeviceName,null);
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        await manager.SelectBackendAsync(true);var commands=new List<PhysicalCommandEvidence>();
        void Record(PhysicalCommandEvidence e){commands.Add(e);Save("commands.json",commands);}
        try
        {
            await manager.ConnectAsync();
            if(real.Observation is not {IsLive:true,SessionId:{} session} || real.Identity.Firmware!="1.0" || PhysicalControlRuntime.DeviceHash(real)!=hash)throw new InvalidOperationException("AD1E live identity/firmware check failed; no runtime command sent.");
            Save("baseline.json",new{real.Observation,Status=real.Diagnostics.LastStatusQuery,Capabilities=real.Diagnostics.LastQuery});
            Save("candidate.private.json",new BleRuntimeAcceptance(hash,"1.0",session,false,false,"Phase61 optional BLE trial; visual confirmation pending"));
            using(var marker=new FileStream(Path.Combine(store.Root,"phase61-ble-rgb-attempted.lock"),FileMode.CreateNew,FileAccess.Write,FileShare.None)){JsonSerializer.Serialize(marker,a);marker.Flush(true);}
            Save("approval.json",new{a.Device,a.Effect,a.Neutral,a.ObserverReady,a.UserApproval});
            try{await manager.ExecuteControlsAsync(ApprovedControlPlan.RuntimeEffect(session,a.UserApproval,1),Record);await Task.Delay(TimeSpan.FromSeconds(8));}
            finally
            {
                if(real.Observation is {IsLive:true} && real.Observation.SessionId==session)await manager.ExecuteControlsAsync(ApprovedControlPlan.RuntimeEffect(session,a.UserApproval+"; neutral",0),Record);
                else Save("neutral-unavailable.json",new{Reason="Session lost; no retry/reconnect"});
            }
        }
        finally{await manager.DisconnectAsync();Save("closed.json",new{At=DateTimeOffset.UtcNow,Disconnected=!real.Observation.IsLive,Writes=commands.Count});}
    }
    public static void Promote(string output,string visualFile)
    {
        var visual=JsonSerializer.Deserialize<Visual>(File.ReadAllText(visualFile))??throw new InvalidOperationException();
        var candidate=JsonSerializer.Deserialize<BleRuntimeAcceptance>(File.ReadAllText(Path.Combine(output,"candidate.private.json")))??throw new InvalidOperationException();
        var commands=JsonSerializer.Deserialize<List<PhysicalCommandEvidence>>(File.ReadAllText(Path.Combine(output,"commands.json")))??[];
        if(!visual.EffectObserved || !visual.NeutralObserved || string.IsNullOrWhiteSpace(visual.UserStatement) || commands.Count!=2 || !commands.Select(x=>x.Tx).SequenceEqual(new[]{"AABB9101CCDD","AABB9100CCDD"}) || commands.Any(x=>x.Transport!=PhysicalTransportKind.Bluetooth || x.Session!=candidate.Session || x.Error is not null || x.Rx!="AABB9100CCDD"))throw new InvalidOperationException("Both ACKs and separate visual confirmation required.");
        var path=Path.Combine(new SettingsStore().Root,"ble-runtime-acceptance.json");
        if(File.Exists(path))throw new InvalidOperationException("BLE proof already exists; no overwrite.");
        File.WriteAllText(path,JsonSerializer.Serialize(candidate with{EffectObserved=true,NeutralObserved=true,Evidence="Phase61: both runtime effects ACKed and user visually confirmed"},Json));
        File.WriteAllText(Path.Combine(output,"visual-confirmation.json"),JsonSerializer.Serialize(visual,Json));
    }
}

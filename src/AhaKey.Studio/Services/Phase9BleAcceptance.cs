using System.IO;
using System.Text.Json;
using System.Windows;
using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Device.Ble;
using AhaKey.Protocol;
using AhaKey.Services;
using AhaKey.Studio.Views;
using Microsoft.Extensions.Logging.Abstractions;
namespace AhaKey.Studio.Services;
public static class Phase9BleAcceptance
{
    // Observation only: no device connection, configuration command, or retry.
    public static async Task ObserveKeysAsync(string output)
    {
        var store=new SettingsStore();using var owner=new SingleInstanceOwner(store.Root);
        if(!owner.IsPrimary)throw new InvalidOperationException("Close Studio first.");
        var settings=store.Load();using var theme=new ThemeService();theme.Apply(settings.Theme);
        var l=new LocalizationService();l.Apply(settings.Language);
        foreach(var key in new[]{PhysicalKey.K2,PhysicalKey.K3,PhysicalKey.K4})
        {
            using var baseline=JsonDocument.Parse(File.ReadAllText(Path.Combine(output,$"baseline-{key}.json")));
            if(!ShortcutGesture.TryParse(baseline.RootElement.GetProperty("Shortcut").GetString(),out var shortcut)||shortcut is null)
                throw new InvalidOperationException("Missing observed shortcut baseline.");
            var verification=new PhysicalKeyVerification();verification.Begin();verification.Accept(new(shortcut,""));
            var window=new PhysicalKeyTestWindow(HardwareProfileId.Codex,key,shortcut,verification,l);
            var completion=new TaskCompletionSource<bool>();
            window.Observed+=(observed,matched)=>{
                File.WriteAllText(Path.Combine(output,$"observed-{key}.json"),JsonSerializer.Serialize(new{Key=key.ToString(),Expected=shortcut.Display,Observed=observed.Display,Matched=matched,ObservationOnly=true,At=DateTimeOffset.UtcNow}));
                if(matched)completion.TrySetResult(true);
            };
            window.Closed+=(_,_)=>completion.TrySetResult(false);
            window.Show();window.Activate();
            var completed=await Task.WhenAny(completion.Task,Task.Delay(TimeSpan.FromMinutes(15)));
            window.Close();if(completed!=completion.Task||!await completion.Task)throw new InvalidOperationException("Physical key observation incomplete.");
        }
    }
    public static async Task RunAsync(string output)
    {
        Directory.CreateDirectory(output);var store=new SettingsStore();var settings=store.Load();
        if(settings.BleDeviceName!="AhaKey AD1E"||string.IsNullOrEmpty(settings.BleDeviceId))throw new InvalidOperationException("Expected saved AD1E selection.");
        using var owner=new SingleInstanceOwner(store.Root);if(!owner.IsPrimary)throw new InvalidOperationException("Close Studio first.");
        await using var real=new RealAhaKeyDevice(new(new WindowsGattSessionFactory(),GattContract.WindowsObserved)){Selected=new(settings.BleDeviceId,settings.BleDeviceName,null)};
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        void Save(string name,object data)=>File.WriteAllText(Path.Combine(output,name),JsonSerializer.Serialize(data,new JsonSerializerOptions{WriteIndented=true}));
        void Record(PhysicalCommandEvidence value)=>File.AppendAllText(Path.Combine(output,"commands.jsonl"),JsonSerializer.Serialize(value)+Environment.NewLine);
        void Stage(string value)=>Save("stage.json",new{Stage=value,At=DateTimeOffset.UtcNow});
        const string approval="Phase 9 bounded BLE acceptance; user present and approved; preserve mappings, restore profile and brightness; no firmware update";
        await manager.SelectBackendAsync(true);
        try
        {
            Stage("Connecting");await manager.ConnectAsync();
            if(real.FirmwareIdentity is not {ReportedVersion:"1.4.8",ReportedProtocol:"3.2",ReportedModel:1,Dialect:FirmwareDialect.WindowsContract32} || real.Observation is not {IsLive:true,SessionId:{} session,Status:{WorkMode:{} initialProfile,Brightness:{} initialBrightness}})
                throw new InvalidOperationException("Expected live 1.4.8 / 3.2 AD1E and complete status.");
            Save("baseline.json",new{Unit="AD1E",Transport="Bluetooth",Identity=real.FirmwareIdentity,Status=real.Diagnostics.LastStatusQuery,Capabilities=real.Diagnostics.LastQuery});
            if(initialProfile>3 || initialBrightness is <1 or >100)throw new InvalidOperationException("Cannot restore reported profile/brightness.");
            var values=new Dictionary<PhysicalKey,ShortcutGesture>();
            for(int k=1;k<=3;k++)
            {
                var bytes=await manager.ReadConfigAsync(0,(byte)(8+k),Record);
                var shortcut=KeyResource.Shortcut(bytes.AsSpan())??throw new InvalidOperationException("Unknown key type; do not replace it.");
                values[(PhysicalKey)k]=shortcut;
                Save($"baseline-K{k+1}.json",new{Profile=2,Key=k,Bytes=Convert.ToHexString(bytes.AsSpan()),Shortcut=shortcut.Display});
            }
            Stage("Lighting 01 for 8 seconds");
            await manager.ExecuteControlsAsync(ApprovedControlPlan.RuntimeEffect(session,approval,1),Record);
            try{await Task.Delay(8000);}finally{if(real.Observation.IsLive)await manager.ExecuteControlsAsync(ApprovedControlPlan.RuntimeEffect(session,approval,0),Record);}
            Stage("Brightness temporary then restore");
            var testBrightness=(byte)(initialBrightness==30?60:30);
            try
            {
                await manager.ExecuteControlsAsync(ApprovedControlPlan.Brightness(session,approval,testBrightness),Record);
                await manager.ReadAsync();Save("brightness-test.json",real.Diagnostics.LastStatusQuery!);
                if(real.Observation.Status?.Brightness!=testBrightness)throw new InvalidOperationException("Brightness readback mismatch.");
                await Task.Delay(3000);
            }
            finally{if(real.Observation.IsLive)await manager.ExecuteControlsAsync(ApprovedControlPlan.Brightness(session,approval+" restore",(byte)initialBrightness),Record);}
            await manager.ReadAsync();Save("brightness-restored.json",real.Diagnostics.LastStatusQuery!);
            if(real.Observation.Status?.Brightness!=initialBrightness)throw new InvalidOperationException("Brightness restore mismatch.");
            Stage("Profile switch and restore");
            try
            {
                await manager.ExecuteControlsAsync(ApprovedControlPlan.WorkProfile(session,approval,(HardwareProfileId)(initialProfile==1?2:1)),Record);
                await manager.ReadAsync();Save("profile-test.json",real.Diagnostics.LastStatusQuery!);
                if(real.Observation.Status?.WorkMode!=(initialProfile==1?2:1))throw new InvalidOperationException("Profile readback mismatch.");
            }
            finally{if(real.Observation.IsLive)await manager.ExecuteControlsAsync(ApprovedControlPlan.WorkProfile(session,approval+" restore",(HardwareProfileId)initialProfile),Record);}
            // Key writes preserve the exact supported shortcut read above. Never write an unreadable label.
            foreach(var (key,shortcut) in values)
            {
                var full=KeyWritePlan.Create(HardwareProfileId.Codex,key,new(shortcut,""));
                var minimal=full with{Commands=[full.Commands[0],full.Commands[^1]]};
                await manager.ExecuteControlsAsync(ApprovedControlPlan.Key(session,approval,minimal),Record);
                var after=await manager.ReadConfigAsync(0,(byte)(8+(int)key),Record);
                if(KeyResource.Shortcut(after.AsSpan())?.Display!=shortcut.Display)throw new InvalidOperationException("Shortcut readback mismatch.");
                Save($"written-{key}.json",new{Shortcut=shortcut.Display,Readback=Convert.ToHexString(after.AsSpan()),LabelUntouched=true});
            }
            // Physical observation in the intended profile; restore the user's original profile on exit.
            if(initialProfile!=2)await manager.ExecuteControlsAsync(ApprovedControlPlan.WorkProfile(session,approval,HardwareProfileId.Codex),Record);
            try
            {
                using var theme=new ThemeService();theme.Apply(settings.Theme);
                var l=new LocalizationService();l.Apply(settings.Language);
                foreach(var (key,shortcut) in values)
                {
                    Stage("Press "+key);var verification=new PhysicalKeyVerification();verification.Begin();verification.Accept(new(shortcut,""));
                    var window=new PhysicalKeyTestWindow(HardwareProfileId.Codex,key,shortcut,verification,l);
                    var completion=new TaskCompletionSource<bool>();
                    window.Observed+=(observed,matched)=>{Save($"observed-{key}.json",new{Transport="Bluetooth configuration route; host key event",Key=key.ToString(),Expected=shortcut.Display,Observed=observed.Display,Matched=matched});if(matched)completion.TrySetResult(true);};
                    window.Closed+=(_,_)=>completion.TrySetResult(false);window.Show();
                    var completed=await Task.WhenAny(completion.Task,Task.Delay(TimeSpan.FromMinutes(3)));
                    window.Close();if(completed!=completion.Task||!await completion.Task)throw new InvalidOperationException("Physical key observation incomplete.");
                }
            }
            finally{if(initialProfile!=2 && real.Observation.IsLive)await manager.ExecuteControlsAsync(ApprovedControlPlan.WorkProfile(session,approval+" restore after key test",(HardwareProfileId)initialProfile),Record);}
            await manager.ReadAsync();Save("final-status.json",real.Diagnostics.LastStatusQuery!);Stage("Completed; visual confirmation pending");
        }
        finally{await manager.DisconnectAsync();Save("closed.json",new{At=DateTimeOffset.UtcNow,Disconnected=!real.Observation.IsLive,Retry=false,FirmwareWrites=false});}
    }
}

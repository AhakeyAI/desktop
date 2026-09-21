using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows;
using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Device.Ble;
using AhaKey.Device.Usb;
using AhaKey.Protocol;
using AhaKey.Services;
using AhaKey.Studio.Views;
using Microsoft.Extensions.Logging.Abstractions;
namespace AhaKey.Studio.Services;

public sealed record PhysicalKeyApproval(string Device,int Profile,string Key,string Shortcut,string Label,string[] Commands,string UserApproval);
public static class PhysicalControlsAcceptance
{
    private static readonly JsonSerializerOptions Json=new(){WriteIndented=true,Converters={new JsonStringEnumConverter()}};
    private static void Save(string output,string name,object value)=>File.WriteAllText(Path.Combine(output,name),JsonSerializer.Serialize(value,Json));
    public static async Task RunLightingAsync(string output,string approvalPath,bool visualTrial=false)
    {
        output=Path.GetFullPath(output);Directory.CreateDirectory(output);
        using var approvalDoc=JsonDocument.Parse(File.ReadAllText(approvalPath));
        var a=approvalDoc.RootElement;
        if(a.GetProperty("Device").GetString()!="AD1E" || a.GetProperty("Transport").GetString()!="USB" ||
           a.GetProperty("Effect").GetString()!="AABB9101CCDD" || a.GetProperty("Neutral").GetString()!="AABB9100CCDD" ||
           string.IsNullOrWhiteSpace(a.GetProperty("UserApproval").GetString()))throw new InvalidOperationException("Lighting approval does not match the prepared trial.");
        var approval=a.GetProperty("UserApproval").GetString()!;
        if(visualTrial && (!a.TryGetProperty("UserPresent",out var present) || !present.GetBoolean()))
            throw new InvalidOperationException("Visual trial requires an observer at AD1E.");
        var store=new SettingsStore();using var owner=new SingleInstanceOwner(store.Root);
        if(!owner.IsPrimary)throw new InvalidOperationException("Close Studio and Key Test before this trial.");
        await using var real=new RealAhaKeyDevice(new(new WindowsGattSessionFactory(),GattContract.WindowsObserved),new(new WindowsHidSessionFactory()));
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        var ledger=new List<PhysicalCommandEvidence>();
        void Record(PhysicalCommandEvidence e){ledger.Add(e);Save(output,"lighting-command-ledger.json",ledger);}
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);
        try
        {
            await manager.ConnectAsync();
            if(real.Observation is not {IsLive:true,SessionId:{} session})throw new InvalidOperationException("No validated USB session.");
            Save(output,"baseline-status.json",new{Unit="AD1E (user-designated)",real.Observation,StatusQuery=real.Usb!.Diagnostics.LastStatusQuery});
            var existingPath=Path.Combine(store.Root,"physical-controls-acceptance.json");
            if(visualTrial)
            {
                var existing=File.Exists(existingPath)?JsonSerializer.Deserialize<ControlAcceptance>(File.ReadAllText(existingPath),Json):null;
                if(existing is null || existing.DeviceHash!=PhysicalControlRuntime.DeviceHash(real) || existing.Firmware!=real.Identity.Firmware)
                    throw new InvalidOperationException("USB identity/firmware differs from accepted AD1E; no effect sent.");
                Save(output,"private-unit-identity.json",existing);
            }
            using(var marker=new FileStream(Path.Combine(store.Root,visualTrial?"phase4b-completion-rgb-visual-trial.lock":"phase4b-first-lighting-attempted.lock"),FileMode.CreateNew,FileAccess.Write,FileShare.None))
            {JsonSerializer.Serialize(marker,new{At=DateTimeOffset.UtcNow,Approval=a});marker.Flush(true);}
            Save(output,"approved-operation.json",a);
            // The user identified this same USB unit as AD1E. Keep host identity private;
            // acceptance applies only to this path + reported firmware, not all legacy devices.
            var proof=Path.Combine(Path.GetDirectoryName(output)!,"phase4b-key-physical","key-behavior.json");
            bool keyVerified=false;
            if(File.Exists(proof)){using var document=JsonDocument.Parse(File.ReadAllText(proof));keyVerified=document.RootElement.GetProperty("Matched").GetBoolean() && document.RootElement.GetProperty("Observed").GetString()=="Ctrl+Enter";}
            if(!visualTrial)File.WriteAllText(existingPath,JsonSerializer.Serialize(new ControlAcceptance(PhysicalControlRuntime.DeviceHash(real)!,real.Identity.Firmware,keyVerified,[],"AD1E user-designated same USB unit; key behavior ledger; RGB visual observation pending"),Json));
            Save(output,"write-intent.json",new{At=DateTimeOffset.UtcNow,Session=session,Commands=new[]{"AABB9101CCDD","AABB9100CCDD"},HoldSeconds=8,Retries=0,Persist=false});
            try
            {
                await manager.ExecuteControlsAsync(ApprovedControlPlan.RuntimeEffect(session,approval,1),Record);
                await Task.Delay(TimeSpan.FromSeconds(8));
            }
            finally
            {
                // One neutral operation in the same session only. A failed effect closes the session;
                // never reconnect/replay automatically to attempt a restoration of uncertain state.
                if(real.Observation is {IsLive:true} && real.Observation.SessionId==session)
                    await manager.ExecuteControlsAsync(ApprovedControlPlan.RuntimeEffect(session,approval+"; approved neutral off",0),Record);
                else Save(output,"restoration-unavailable.json",new{Reason="Session closed; no automatic reconnect or retry",At=DateTimeOffset.UtcNow});
            }
        }
        finally{await manager.DisconnectAsync();Save(output,"closed.json",new{At=DateTimeOffset.UtcNow,Disconnected=!real.Observation.IsLive,ReaderStopped=!real.Usb!.Diagnostics.ReaderRunning,Writes=ledger.Count});}
    }
    public static async Task RunAsync(string output,string? approvalPath=null)
    {
        output=Path.GetFullPath(output);Directory.CreateDirectory(output);
        var store=new SettingsStore();using var owner=new SingleInstanceOwner(store.Root);
        if(!owner.IsPrimary)throw new InvalidOperationException("Close normal Studio before physical acceptance.");
        await using var real=new RealAhaKeyDevice(new(new WindowsGattSessionFactory(),GattContract.WindowsObserved),new(new WindowsHidSessionFactory()));
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        var ledger=new List<PhysicalCommandEvidence>();
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);
        try
        {
            await manager.ConnectAsync();if(!real.Observation.IsLive)throw new InvalidOperationException("No validated USB session; no write attempted.");
            Save(output,"baseline-status.json",new{Unit="AD1E (user-designated)",real.Observation,StatusQuery=real.Usb!.Diagnostics.LastStatusQuery});
            ShortcutGesture.TryParse("Ctrl+Enter",out var gesture);
            var plan=KeyWritePlan.Create(HardwareProfileId.Codex,PhysicalKey.K2,new(gesture!,"Send"));
            Save(output,"key-write-preview.json",new{Device="AD1E",Transport="USB",Profile=2,Key="K2",PreviousPhysicalConfiguration="Unknown; no backup/readback",NewShortcut=gesture!.Display,NewLabel="Send",Commands=plan.Commands.Select(c=>Convert.ToHexString(c.Frame.AsSpan())),Save04=true,SaveScope="Global firmware configuration save; no per-key save exists",CurrentPhysicalProfile=real.Observation.Status!.WorkMode,OtherKeyOrProfileWrites=0,LightingWrites=0,DisplayWrites=0,AutomaticRetries=0});
            if(approvalPath is null)return;
            var approval=JsonSerializer.Deserialize<PhysicalKeyApproval>(File.ReadAllText(approvalPath),Json)??throw new InvalidOperationException("Missing approval.");
            if(approval.Device!="AD1E" || approval.Profile!=2 || approval.Key!="K2" || approval.Shortcut!="Ctrl+Enter" || approval.Label!="Send" || string.IsNullOrWhiteSpace(approval.UserApproval) || !approval.Commands.SequenceEqual(plan.Commands.Select(c=>Convert.ToHexString(c.Frame.AsSpan()))))throw new InvalidOperationException("Approval differs from exact prepared operation.");
            if(real.Observation.Status.WorkMode!=2)throw new InvalidOperationException("Physical profile is not Codex/2; no mode change or key write was sent.");
            var marker=Path.Combine(store.Root,"phase4b-first-key-write-attempted.lock");Directory.CreateDirectory(store.Root);
            using(var once=new FileStream(marker,FileMode.CreateNew,FileAccess.Write,FileShare.None)){JsonSerializer.Serialize(once,new{At=DateTimeOffset.UtcNow,Approval=approval});once.Flush(true);}
            Save(output,"approved-operation.json",approval);
            var verification=new PhysicalKeyVerification();verification.Begin();
            try{await manager.ExecuteControlsAsync(ApprovedControlPlan.Key(real.Observation.SessionId!.Value,approval.UserApproval,plan),e=>{ledger.Add(e);Save(output,"key-command-ledger.json",ledger);});verification.Accept(plan.Value);}
            catch{verification.Fail();throw;}
            var l=new LocalizationService();l.Apply(LanguageChoice.Russian);new ThemeService().Apply(ThemeChoice.Light);
            var window=new PhysicalKeyTestWindow(plan,verification,l);Application.Current.MainWindow=window;
            var closed=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            window.Closed+=(_,_)=>closed.TrySetResult();
            window.Observed+=(observed,matched)=>
            {
                Save(output,"key-behavior.json",new{At=DateTimeOffset.UtcNow,Expected=plan.Value.Shortcut.Canonical,Observed=observed.Canonical,Matched=matched,State=verification.State,Input="Focused WPF keyboard event; user must press AhaKey; no injected input or global hook",ReadbackVerified=false});
                if(matched)_=StudioSmokeTest.Capture(window,output,"physical-key-behavior");
            };
            window.Show();Save(output,"key-test-ready.json",new{At=DateTimeOffset.UtcNow,Expected=plan.Value.Shortcut.Display,Key="K2",Profile=2});
            await closed.Task.WaitAsync(TimeSpan.FromMinutes(15));
        }
        finally{await manager.DisconnectAsync();Save(output,"closed.json",new{At=DateTimeOffset.UtcNow,Disconnected=!real.Observation.IsLive,ReaderStopped=!real.Usb!.Diagnostics.ReaderRunning,Writes=ledger.Count});}
    }
}

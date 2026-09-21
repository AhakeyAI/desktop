using System.IO;
using System.Text.Json;
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

public sealed record K1TrialApproval(string Device,string Transport,int Profile,int Key,string[] Commands,string UserApproval);
public static class K1PhysicalAcceptance
{
    private static readonly JsonSerializerOptions Json=new(){WriteIndented=true};
    public static readonly string[] Commands=["AABB737302006ECCDD","AABB04CCDD","AABB737302006DCCDD","AABB04CCDD"];
    public static async Task RunAsync(string output,string approvalPath)
    {
        output=Path.GetFullPath(output);Directory.CreateDirectory(output);
        void Save(string name,object value)=>File.WriteAllText(Path.Combine(output,name),JsonSerializer.Serialize(value,Json));
        var approval=JsonSerializer.Deserialize<K1TrialApproval>(File.ReadAllText(approvalPath))??throw new InvalidOperationException("Missing approval.");
        if(approval.Device!="AD1E" || approval.Transport!="USB" || approval.Profile!=2 || approval.Key!=0 ||
            !approval.Commands.SequenceEqual(Commands) || string.IsNullOrWhiteSpace(approval.UserApproval))throw new InvalidOperationException("Approval differs from the exact K1 experiment.");
        var settings=new SettingsStore();using var owner=new SingleInstanceOwner(settings.Root);
        if(!owner.IsPrimary)throw new InvalidOperationException("Close Studio before the K1 experiment.");
        var path=Path.Combine(settings.Root,"physical-controls-acceptance.json");
        var acceptance=JsonSerializer.Deserialize<ControlAcceptance>(File.ReadAllText(path))??throw new InvalidOperationException("No accepted unit identity.");
        var factory=new WindowsHidSessionFactory();
        var candidate=HidSelectionPolicy.Select(await factory.EnumerateAsync(default)).Candidate??throw new InvalidOperationException("No unique validated USB device.");
        var hash=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes("Usb:"+candidate.Path)));
        if(hash!=acceptance.DeviceHash)throw new InvalidOperationException("USB identity changed; nothing transmitted.");
        await using var real=new RealAhaKeyDevice(new(new WindowsGattSessionFactory(),GattContract.WindowsObserved),new(factory));
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        var ledger=new List<PhysicalCommandEvidence>();ReversibleK1Trial? trial=null;
        void Record(PhysicalCommandEvidence value){ledger.Add(value);Save("command-ledger.json",ledger);}
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);
        try
        {
            await manager.ConnectAsync();
            if(real.Observation is not {IsLive:true,SessionId:{} session,Status:{WorkMode:2}} || real.Identity.Firmware!=acceptance.Firmware || PhysicalControlRuntime.DeviceHash(real)!=acceptance.DeviceHash)
                throw new InvalidOperationException("Expected accepted AD1E USB firmware and active profile 2; no K1 write.");
            Save("baseline.json",new{At=DateTimeOffset.UtcNow,Session=session,real.Identity.Firmware,Profile=2,Status=real.Usb!.Diagnostics.LastStatusQuery});
            trial=new(session,approval.UserApproval);
            var l=new LocalizationService();l.Apply(LanguageChoice.Russian);new ThemeService().Apply(ThemeChoice.Light);
            async Task<bool> Observe(string stage,string expected)
            {
                ShortcutGesture.TryParse(expected,out var gesture);
                var plan=new KeyWritePlan(HardwareProfileId.Codex,PhysicalKey.K1,new(gesture!,""),[]);
                var verification=new PhysicalKeyVerification();verification.Begin();verification.Accept(plan.Value);
                var window=new PhysicalKeyTestWindow(plan,verification,l);Application.Current.MainWindow=window;
                var match=new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                window.Closed+=(_,_)=>match.TrySetResult(false);
                window.Observed+=(value,matched)=>
                {
                    File.AppendAllText(Path.Combine(output,"keyboard-events.jsonl"),JsonSerializer.Serialize(new{At=DateTimeOffset.UtcNow,Session=session,Stage=stage,Expected=expected,Observed=value.Canonical,Matched=matched,Input="Focused WPF event; user physical press, no injected input"})+Environment.NewLine);
                    if(matched)match.TrySetResult(true);
                };
                window.Show();Save("stage.json",new{Stage=stage,Expected=expected,At=DateTimeOffset.UtcNow,WaitSeconds=120});
                bool result;
                try{result=await match.Task.WaitAsync(TimeSpan.FromSeconds(120));}
                catch(TimeoutException){result=false;}
                // Let the user's key-up settle before the next firmware mapping.
                await Task.Delay(700);window.Close();return result;
            }
            if(!await Observe("baseline-F18","F18"))throw new InvalidOperationException("Baseline F18 not observed; no K1 write.");
            trial.ObserveBaseline("F18");
            using(var marker=new FileStream(Path.Combine(settings.Root,"phase5-k1-attempted.lock"),FileMode.CreateNew,FileAccess.Write,FileShare.None))
            {JsonSerializer.Serialize(marker,new{At=DateTimeOffset.UtcNow,Approval=approval});marker.Flush(true);}
            Save("approved-operation.json",approval);Save("private-acceptance-before.json",acceptance);
            File.WriteAllText(path,JsonSerializer.Serialize(acceptance with{K1=null},Json));
            try
            {
                await manager.ExecuteControlsAsync(trial.BeginTest(),Record);trial.TestAccepted();
                if(await Observe("test-F19","F19"))trial.ObserveTest("F19");else trial.Fail();
            }
            catch {trial.Fail();throw;}
            finally
            {
                // Restore once even after a missing/mismatched key observation. Never reconnect/retry.
                if(real.Observation is {IsLive:true} && real.Observation.SessionId==session)
                {
                    try
                    {
                        await manager.ExecuteControlsAsync(trial.BeginRestore(),Record);trial.RestoreAccepted();
                        if(await Observe("restore-F18","F18"))trial.ObserveRestore("F18");else trial.Fail();
                    }
                    catch {trial.Fail();throw;}
                }
                else {trial.Fail();Save("restore-unavailable.json",new{Reason="Session lost; no reconnect or automatic retry",At=DateTimeOffset.UtcNow});}
            }
            Save("behavior-evidence.json",trial.Evidence);
            if(trial.Evidence.PromotesCapability)
                File.WriteAllText(path,JsonSerializer.Serialize(acceptance with{K1=trial.Evidence},Json));
        }
        finally
        {
            if(trial is not null)Save("behavior-evidence.json",trial.Evidence);
            await manager.DisconnectAsync();Save("closed.json",new{At=DateTimeOffset.UtcNow,Disconnected=!real.Observation.IsLive,ReaderStopped=!real.Usb!.Diagnostics.ReaderRunning,Writes=ledger.Count});
        }
    }
}

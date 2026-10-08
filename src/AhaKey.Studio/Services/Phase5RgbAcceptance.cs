using System.IO;
using System.Text.Json;
using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Device.Ble;
using AhaKey.Device.Usb;
using AhaKey.Integrations;
using AhaKey.Services;
using Microsoft.Extensions.Logging.Abstractions;
namespace AhaKey.Studio.Services;

// Explicit acceptance entry point. Real installed hook server; no synthetic event injection.
public static class Phase5RgbAcceptance
{
    public static async Task RunAsync(string output)
    {
        output=Path.GetFullPath(output);Directory.CreateDirectory(output);object journal=new();
        void Save(string name,object value){lock(journal)File.WriteAllText(Path.Combine(output,name),JsonSerializer.Serialize(value,new JsonSerializerOptions{WriteIndented=true}));}
        var settings=new SettingsStore();using var owner=new SingleInstanceOwner(settings.Root);if(!owner.IsPrimary)throw new InvalidOperationException("Close Studio before RGB acceptance.");
        await using var real=new RealAhaKeyDevice(new(new WindowsGattSessionFactory(),GattContract.WindowsObserved),new(new WindowsHidSessionFactory()));
        using var manager=new DeviceManager(new MockAhaKeyDevice(),new(),NullLogger<DeviceManager>.Instance,real);
        var runtime=new PhysicalControlRuntime(manager,settings);var hooks=CodexAcceptance.Create();var feedback=new PhysicalFeedbackService(manager);
        var effects=new HashSet<byte>{0,1};var map=new Dictionary<IdeEventState,byte>{{IdeEventState.UserPromptSubmit,1},{IdeEventState.Stop,0}};
        var ledger=new List<PhysicalCommandEvidence>();var effectSeen=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var neutralSeen=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);var eventGate=new SemaphoreSlim(1,1);
        bool enabled=false;DateTimeOffset? litAt=null;
        void Record(PhysicalCommandEvidence e){ledger.Add(e);Save("command-ledger.json",ledger);}
        await manager.SelectBackendAsync(true);await manager.SelectTransportAsync(PhysicalTransportKind.Usb);
        try
        {
            await manager.ConnectAsync();
            if(real.Observation is not {IsLive:true,SessionId:{} session,Status:{WorkMode:2}} || !runtime.Effects.Contains(0) || !runtime.Effects.Contains(1))
                throw new InvalidOperationException("Accepted AD1E USB RGB effects and active profile 2 required.");
            await hooks.RefreshAsync();var status=hooks.Statuses.Single(s=>s.Id==AssistantId.Codex);
            // Existing legacy AhaKey hooks use the same normalized endpoint. Do not reinstall or
            // alter native trust to manufacture Studio-owned configuration evidence.
            if(status.Installed!=EvidenceState.Yes || status.Compatible!=EvidenceState.Yes)throw new InvalidOperationException("Installed Codex event contract is not ready.");
            Save("host-boundary.json",new{status.Version,StudioOwnedConfigured=status.Configured.ToString(),StudioOwnedEnabled=status.Enabled.ToString(),Source="Existing installed Codex hooks; native trust enforced by Codex",ConfigurationModified=false});
            using(var marker=new FileStream(Path.Combine(settings.Root,"phase5-live-codex-rgb-attempted.lock"),FileMode.CreateNew,FileAccess.Write,FileShare.None)){marker.Flush(true);}
            hooks.Server.EventReceived+=async ev=>
            {
                await eventGate.WaitAsync();
                try
                {
                    if(ev.Event==IdeEvent.Stop && litAt is {} at && DateTimeOffset.UtcNow-at<TimeSpan.FromSeconds(3))await Task.Delay(TimeSpan.FromSeconds(3)-(DateTimeOffset.UtcNow-at));
                    var input=new FeedbackInput(session,HardwareProfileId.Codex,ev.Integration.ToString(),(IdeEventState)ev.Event,ev.NativeEvent);
                    bool accepted=await feedback.HandleAsync(input,enabled && ev.Integration==AssistantId.Codex,map,effects,Record,report:decision=>
                    {
                        lock(journal)File.AppendAllText(Path.Combine(output,"normalized-events.jsonl"),JsonSerializer.Serialize(new{At=DateTimeOffset.UtcNow,Session=session,Integration=ev.Integration.ToString(),Event=ev.Event.ToString(),ev.NativeEvent,Result=decision.Disposition.ToString(),decision.Effect})+Environment.NewLine);
                    });
                    if(accepted && ev.Event==IdeEvent.UserPromptSubmit){litAt=DateTimeOffset.UtcNow;effectSeen.TrySetResult();}
                    if(accepted && ev.Event==IdeEvent.Stop){enabled=false;neutralSeen.TrySetResult();}
                }
                catch(Exception ex){enabled=false;Save("event-error.json",new{Error=ex.GetType().Name});neutralSeen.TrySetException(ex);}
                finally{eventGate.Release();}
            };
            enabled=true;
            if(!hooks.Server.Start())throw new InvalidOperationException("Port 8765 unavailable; no fallback.");
            Save("ready.json",new{At=DateTimeOffset.UtcNow,Session=session,Profile=2,Integration="Codex",FeedbackEnabled=true,AllowedEvents=new[]{"UserPromptSubmit -> 01","Stop -> 00"},OtherEvents="No output",HardwareAuto=false,MinimumVisibleSeconds=3,MaximumWaitSeconds=60});
            await effectSeen.Task.WaitAsync(TimeSpan.FromSeconds(60));
            try{await neutralSeen.Task.WaitAsync(TimeSpan.FromSeconds(30));}catch(TimeoutException){Save("neutral-trigger.json",new{Trigger="Bounded manual reset; Stop not received"});}
        }
        finally
        {
            enabled=false;hooks.Approvals.Dispose();await hooks.Server.DisposeAsync();await eventGate.WaitAsync();
            try
            {
                if(litAt is not null && !neutralSeen.Task.IsCompletedSuccessfully && real.Observation is {IsLive:true,SessionId:{} session})
                    await manager.ExecuteControlsAsync(ApprovedControlPlan.RuntimeEffect(session,"Phase 5 accepted runtime scope; bounded manual neutral reset",0),Record);
            }
            finally
            {
                eventGate.Release();Save("counters.json",new{feedback.Received,feedback.SuppressedDuplicates,feedback.PhysicalOperations,feedback.SuccessfulOperations});
                await manager.DisconnectAsync();Save("closed.json",new{At=DateTimeOffset.UtcNow,FeedbackEnabled=false,ServiceStopped=!hooks.Server.Running,Disconnected=!real.Observation.IsLive,ReaderStopped=!real.Usb!.Diagnostics.ReaderRunning,Writes=ledger.Count});
            }
        }
    }
}

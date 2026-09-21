using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Protocol;
using AhaKey.Services;
namespace AhaKey.Studio.Services;

public sealed record ControlAcceptance(string DeviceHash,string Firmware,bool KeyBehaviorVerified,byte[] VisuallyVerifiedEffects,string Evidence)
{public K1BehaviorEvidence? K1 {get;init;}public StaticDisplayAcceptance? StaticDisplay {get;init;}public ProfileSwitchAcceptance? ProfileSwitch {get;init;}}
public sealed class ProductRouteException(string key):InvalidOperationException(key) {public string Key {get;}=key;}
public sealed class PhysicalControlRuntime(DeviceManager manager,SettingsStore settings,ProfileSelectionService? preferences=null,RealDeviceRuntime? connections=null)
{
    public bool UsbOperationBusy {get;private set;}
    public string? RouteNotice {get;private set;}
    public object DiagnosticGates=>new
    {
        manager.RealBackendSelected,ActiveTransport=manager.RealDevice?.ActiveTransport.ToString(),
        Connected=manager.RealDevice?.Observation.IsLive??false,Firmware=manager.RealDevice?.Identity.Firmware,
        SavedBleSelection=manager.RealDevice?.Selected is not null,BleConnected=manager.RealDevice?.Diagnostics.IsLive??false,
        UsbEnumerated=manager.RealDevice?.Usb?.Diagnostics.History.Any(x=>x.Event=="Enumeration")??false,
        UsbCandidates=manager.RealDevice?.Usb?.Diagnostics.Candidates.Count??0,
        PrivateUsbReceiptPresent=StoredUsbAcceptance is not null,UsbIdentityAndFirmwareMatch=Acceptance is not null,
        KeyAvailable,FeedbackAvailable,AcceptedRuntimeEffects=Effects.Order().ToArray(),UsbOperationBusy
    };
    private readonly ProfileSelectionService preferences=preferences??new(settings);
    private long aggregateOperations,aggregateSuccess;
    private Guid? failedFeedbackSession;
    private (Guid Session,HardwareProfileId Profile,byte Code)? lastFeedback;
    private readonly PhysicalFeedbackService feedback=new(manager);
    private readonly object journalSync=new();
    public event Action? Changed;
    public string? LastError {get;private set;}
    public int DisplayBlocksConfirmed {get;private set;}
    public string? DisplayLastConfirmed {get;private set;}
    public bool DisplayBindingConfirmed {get;private set;}
    public bool DisplaySaveConfirmed {get;private set;}
    public long ReceivedEvents=>feedback.Received;
    public long SuppressedDuplicates=>feedback.SuppressedDuplicates;
    public long FeedbackOperations=>feedback.PhysicalOperations+Interlocked.Read(ref aggregateOperations);
    public long AcceptedFeedbackOperations=>feedback.SuccessfulOperations+Interlocked.Read(ref aggregateSuccess);
    public event Action<FeedbackInput,FeedbackDecision>? FeedbackObserved;
    public static string? DeviceHash(RealAhaKeyDevice? real)
    {
        if(real is null || !real.Observation.IsLive)return null;
        var identity=real.ActiveTransport==PhysicalTransportKind.Usb?real.Usb?.Diagnostics.Selected?.Path:real.Selected?.Id;
        return identity is null?null:Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(real.ActiveTransport+":"+identity)));
    }
    public ControlAcceptance? StoredUsbAcceptance
    {
        get
        {
            try
            {
                var path=Path.Combine(settings.Root,"physical-controls-acceptance.json");if(!File.Exists(path))return null;
                var a=JsonSerializer.Deserialize<ControlAcceptance>(File.ReadAllText(path));
                return a;
            }
            catch(Exception ex)when(ex is IOException or JsonException or UnauthorizedAccessException){return null;}
        }
    }
    public ControlAcceptance? Acceptance=>StoredUsbAcceptance is {} a && manager.RealDevice?.ActiveTransport==PhysicalTransportKind.Usb && a.DeviceHash==DeviceHash(manager.RealDevice) && a.Firmware==manager.RealDevice?.Identity.Firmware?a:null;
    public DeviceFeatureCatalog Features => new(manager.RealDevice?.FirmwareIdentity??FirmwareIdentity.Unknown,
        manager.RealDevice?.ActiveTransport==PhysicalTransportKind.Usb?FeatureTransport.Usb:FeatureTransport.Bluetooth,
        new(Acceptance?.KeyBehaviorVerified==true,Acceptance?.StaticDisplay?.PromotesCapability==true,Effects.Contains(1),Effects.Contains(0)));
    public bool KeyAvailable=>manager.RealBackendSelected && manager.RealDevice?.Observation.IsLive==true && Features.CanWriteShortcut(HardwareProfileId.Codex,PhysicalKey.K2).Available;
    public bool StaticDisplayAvailable=>manager.RealBackendSelected && Features.CanUploadDisplay(HardwareProfileId.Codex,DisplayState.Default,1).Available;
    public IReadOnlySet<byte> Effects
    {
        get
        {
            if(manager.RealDevice?.Observation.IsLive==true && manager.RealDevice.FirmwareIdentity is {Dialect:FirmwareDialect.WindowsContract32,ReportedVersion:"1.4.8",ReportedProtocol:"3.2",ReportedModel:1})return Enumerable.Range(0,17).Select(x=>(byte)x).ToHashSet();
            if(manager.RealDevice?.ActiveTransport!=PhysicalTransportKind.Bluetooth)return (Acceptance?.VisuallyVerifiedEffects??[]).Where(x=>x<=0x10).ToHashSet();
            try
            {
                var path=Path.Combine(settings.Root,"ble-runtime-acceptance.json");
                var proof=File.Exists(path)?JsonSerializer.Deserialize<BleRuntimeAcceptance>(File.ReadAllText(path)):null;
                return proof?.Matches(DeviceHash(manager.RealDevice),manager.RealDevice.Identity.Firmware)==true?new HashSet<byte>{0,1}:new HashSet<byte>();
            }
            catch(Exception ex)when(ex is IOException or JsonException or UnauthorizedAccessException){return new HashSet<byte>();}
        }
    }
    public bool FeedbackEnabled(HardwareProfileId profile,string integration)=>preferences.Settings.PhysicalFeedback.Contains($"{(int)profile}:{integration}");
    public bool FeedbackOperational(HardwareProfileId profile,string integration)=>!UsbOperationBusy && FeedbackEnabled(profile,integration) && manager.RealDevice?.Observation is {IsLive:true,SessionId:{} id} && failedFeedbackSession!=id;
    public bool FeedbackAvailable=>manager.RealBackendSelected && manager.RealDevice?.Observation.IsLive==true && Features.CanUseRuntimeLighting(0).Available && Features.CanUseRuntimeLighting(1).Available;
    public string FeedbackStateKey(HardwareProfileId profile,string integration)=>!FeedbackEnabled(profile,integration)?"ProductOff":FeedbackAvailable?"ProductOn":"ProductConnectUsb";
    // Unique source-known HID interface is handshaken before feature gating; legacy still needs its receipt.
    // The callback is invoked after the normal 00/9F handshake validates firmware, never from discovery alone.
    public async Task WithKeyRouteAsync(Func<Task> write)
    {
        var requirement=manager.Operations.SelectTransport(OperationRequirement.WriteShortcut,manager.RealDevice?.ActiveTransport,KeyAvailable);
        if(requirement==manager.RealDevice?.ActiveTransport && KeyAvailable){await write();return;}
        if(requirement==PhysicalTransportKind.Bluetooth && connections is not null && manager.RealDevice?.Selected is not null)
        {
            if(manager.RealDevice.ActiveTransport!=requirement)await connections.SelectTransportAsync(requirement);
            if(!manager.RealDevice.Observation.IsLive)await connections.ConnectAsync();
            if(KeyAvailable){await write();return;}
        }
        await WithUsbAsync(write,true,true);
    }
    public Task ConnectFeedbackUsbAsync()=>WithUsbAsync(()=>Task.CompletedTask,false,false);
    private async Task WithUsbAsync(Func<Task> action,bool restoreBle,bool key)
    {
        if(UsbOperationBusy || connections is null || !manager.RealBackendSelected || manager.RealDevice?.Usb is null)throw new ProductRouteException("ProductDeviceBusy");
        var real=manager.RealDevice;bool restore=restoreBle && real.ActiveTransport==PhysicalTransportKind.Bluetooth && real.Observation.IsLive;
        var originalBle=real.Selected;bool switched=false;Guid? ownedSession=null;
        UsbOperationBusy=true;RouteNotice=null;Changed?.Invoke();
        try
        {
            if(real.ActiveTransport!=PhysicalTransportKind.Usb || !real.Observation.IsLive)
            {
                var found=await real.Usb.DiscoverAsync();
                if(found.Candidate is not {} candidate)throw new ProductRouteException(found.ErrorKey=="UsbAmbiguous"?"UsbAmbiguous":key?"ProductConnectUsbKeys":"ProductConnectUsbLighting");
                var proof=StoredUsbAcceptance;
                var hash=Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(PhysicalTransportKind.Usb+":"+candidate.Path)));
                if(real.FirmwareIdentity.Dialect==FirmwareDialect.LegacyWindows&&(proof is null||proof.DeviceHash!=hash))throw new ProductRouteException("ProductUsbNotAccepted");
                switched=real.ActiveTransport!=PhysicalTransportKind.Usb;
                if(switched)await connections.SelectTransportAsync(PhysicalTransportKind.Usb);
                await connections.ConnectAsync();ownedSession=real.Observation.SessionId;
            }
            if(!real.Observation.IsLive)throw new ProductRouteException("ProductUsbConnectFailed");
            ownedSession=real.Observation.SessionId;
            if(key?!KeyAvailable:!FeedbackAvailable)throw new ProductRouteException("ProductUsbNotAccepted");
            await action();
        }
        finally
        {
            try
            {
                if(restore && switched && !connections.ExplicitlyDisconnected && real.ActiveTransport==PhysicalTransportKind.Usb && real.Observation.SessionId==ownedSession && real.Selected==originalBle)
                {
                    await connections.SelectTransportAsync(PhysicalTransportKind.Bluetooth);await connections.ConnectAsync();
                    if(!real.Observation.IsLive)RouteNotice="ProductBleRestoreFailed";
                }
            }
            catch(Exception ex)when(ex is not OutOfMemoryException){RouteNotice="ProductBleRestoreFailed";}
            finally{UsbOperationBusy=false;Changed?.Invoke();}
        }
    }
    public void EnableFeedback(HardwareProfileId profile,string integration,bool enabled)
    {
        string key=$"{(int)profile}:{integration}";
        preferences.Update(s=>s with{PhysicalFeedback=enabled?s.PhysicalFeedback.Add(key):s.PhysicalFeedback.Remove(key)});
        failedFeedbackSession=null;LastError=null;Changed?.Invoke();
    }
    public async Task UploadStaticAsync(StaticDisplayPlan plan,string approval)
    {
        if(!StaticDisplayAvailable || manager.RealDevice?.Observation is not {IsLive:true,SessionId:{} session,Status:{WorkMode:2}})
            throw new InvalidOperationException("Static Display not accepted for this active USB device/profile.");
        var directory=Path.Combine(settings.Root,"PhysicalControls","Display",Guid.NewGuid().ToString("N"));Directory.CreateDirectory(directory);
        DisplayBlocksConfirmed=0;DisplayLastConfirmed=null;DisplayBindingConfirmed=false;DisplaySaveConfirmed=false;Changed?.Invoke();
        File.WriteAllBytes(Path.Combine(directory,"frame.rgb565"),plan.Frame.ToArray());
        Intent(new{Operation="Static Display overwrite",Session=session,Profile=2,Slot=9,plan.Sha256,Approval=approval,At=DateTimeOffset.UtcNow});
        await manager.UploadDisplayAsync(new(session,approval,plan.Sha256,plan),
            e=>File.AppendAllText(Path.Combine(directory,"native-writes.jsonl"),JsonSerializer.Serialize(e)+Environment.NewLine),
            e=>{File.AppendAllText(Path.Combine(directory,"responses.jsonl"),JsonSerializer.Serialize(e)+Environment.NewLine);
                if(e.Stage.StartsWith("81 sector",StringComparison.Ordinal))DisplayBlocksConfirmed++;
                DisplayLastConfirmed=e.Stage;DisplayBindingConfirmed|=e.Stage=="82 binding";DisplaySaveConfirmed|=e.Stage=="04 save";Changed?.Invoke();});
    }
    public async Task UploadModernAsync(Windows32DisplayUploadPlan plan,string approval)
    {
        if(manager.RealDevice?.Observation is not {IsLive:true,SessionId:{} session} || !Features.CanUploadDisplay(plan.Transfer.Profile,plan.Transfer.Asset,plan.Transfer.FrameCount).Available)throw new InvalidOperationException("Live Windows 3.2 USB target required.");
        var directory=Path.Combine(settings.Root,"PhysicalControls","Display",Guid.NewGuid().ToString("N"));Directory.CreateDirectory(directory);
        DisplayBlocksConfirmed=0;DisplayLastConfirmed=null;DisplayBindingConfirmed=false;DisplaySaveConfirmed=false;Changed?.Invoke();
        File.WriteAllText(Path.Combine(directory,"plan.json"),JsonSerializer.Serialize(new{plan.Allocation,plan.Sha256,plan.FrameHashes,plan.Transfer.FrameCount,plan.Transfer.IntervalMs,Approval=approval}));
        Intent(new{Operation="Windows 3.2 Display overwrite",Session=session,plan.Allocation,plan.Sha256,At=DateTimeOffset.UtcNow});
        await manager.UploadDisplayAsync(new(session,approval,plan.Sha256,plan),
            e=>File.AppendAllText(Path.Combine(directory,"native-writes.jsonl"),JsonSerializer.Serialize(e)+Environment.NewLine),
            e=>{File.AppendAllText(Path.Combine(directory,"responses.jsonl"),JsonSerializer.Serialize(e)+Environment.NewLine);
                if(e.Stage.StartsWith("81 sector",StringComparison.Ordinal))DisplayBlocksConfirmed++;
                DisplayLastConfirmed=e.Stage;DisplayBindingConfirmed|=e.Stage is "82 binding" or "93 binding";DisplaySaveConfirmed|=e.Stage=="04 save";Changed?.Invoke();});
    }
    public void Record(PhysicalCommandEvidence value)
    {
        lock(journalSync){var folder=Path.Combine(settings.Root,"PhysicalControls");Directory.CreateDirectory(folder);File.AppendAllText(Path.Combine(folder,"commands.jsonl"),JsonSerializer.Serialize(value)+Environment.NewLine);}
    }
    public void Intent(object value)
    {
        lock(journalSync){var folder=Path.Combine(settings.Root,"PhysicalControls");Directory.CreateDirectory(folder);using var stream=new FileStream(Path.Combine(folder,"intents.jsonl"),FileMode.Append,FileAccess.Write,FileShare.Read);using var writer=new StreamWriter(stream,leaveOpen:true);writer.WriteLine(JsonSerializer.Serialize(value));writer.Flush();stream.Flush(true);}
    }
    public async Task PreviewAsync(byte code,string approval)
    {
        if(!Effects.Contains(code)||!Effects.Contains(0)||manager.RealDevice?.Observation.SessionId is not {} session)throw new InvalidOperationException("Effect has not passed physical acceptance for this device.");
        Intent(new{Category="Runtime preview",Session=session,Effect=code,Neutral=0,Approval=approval,At=DateTimeOffset.UtcNow});
        try{await manager.ExecuteControlsAsync(ApprovedControlPlan.RuntimeEffect(session,approval,code),Record);await Task.Delay(2000);}
        finally{if(code!=0 && manager.RealDevice?.Observation is {IsLive:true} o && o.SessionId==session)await manager.ExecuteControlsAsync(ApprovedControlPlan.RuntimeEffect(session,approval+"; neutral off",0),Record);}
    }
    public async Task HandleAsync(HardwareProfileId profile,string integration,IdeEventState ev,string nativeEvent)
    {
        var session=manager.RealDevice?.Observation.SessionId??Guid.Empty;
        try
        {
            var map=integration=="Codex" && !preferences.Settings.AdvancedLightingMapping?CodexFeedbackMapping.Simple:manager.Tracker.Draft.Profiles[profile].Lighting.Mapping;
            var input=new FeedbackInput(session,profile,integration,ev,nativeEvent);
            await feedback.HandleAsync(input,FeedbackOperational(profile,integration),map,Effects,e=>Record(e),beforeSend:(code,id)=>Intent(new{At=DateTimeOffset.UtcNow,Session=id,Profile=profile,Integration=integration,Event=ev,Tx=Convert.ToHexString(LegacyControlCommand.Effect(code).Frame.AsSpan()),Approval="Explicit per-profile integration opt-in"}),report:decision=>
            {
                if(decision is {Disposition:FeedbackDisposition.Accepted,Effect:{} effect})lastFeedback=(session,profile,effect);
                lock(journalSync)
                {
                    var folder=Path.Combine(settings.Root,"PhysicalControls");Directory.CreateDirectory(folder);
                    var path=Path.Combine(folder,"feedback-events.jsonl");
                    if(File.Exists(path) && new FileInfo(path).Length>1024*1024)File.Move(path,path+".previous",true);
                    File.AppendAllText(path,JsonSerializer.Serialize(new{At=DateTimeOffset.UtcNow,Session=session,Profile=profile,Integration=integration,Event=ev.ToString(),NativeEvent=nativeEvent,Result=decision.Disposition.ToString(),decision.Effect})+Environment.NewLine);
                }
                FeedbackObserved?.Invoke(input,decision);Changed?.Invoke();
            },stillEnabled:()=>FeedbackOperational(profile,integration));
        }
        catch(Exception ex) when(ex is not OutOfMemoryException)
        {failedFeedbackSession=session;LastError="PhysicalFeedbackStopped";Changed?.Invoke();}
    }
    public async Task StopFeedbackAsync()
    {
        if(lastFeedback is not {Code:not 0} previous || !Effects.Contains(0))return;
        try
        {
            var sent=await manager.ExecuteFeedbackAsync(ApprovedControlPlan.RuntimeEffect(previous.Session,"Stop integration service; neutralize its active feedback",0),previous.Profile,
                ()=>lastFeedback==previous,()=>Intent(new{At=DateTimeOffset.UtcNow,Session=previous.Session,Operation="Stop service neutral",Tx="AABB9100CCDD"}),Record);
            if(sent)lastFeedback=null;else LastError="PhysicalFeedbackStopped";
        }
        catch(Exception ex)when(ex is not OutOfMemoryException){LastError="PhysicalFeedbackStopped";}
        Changed?.Invoke();
    }
    public async Task ApplyAggregateAsync(HardwareProfileId profile,string? owner,bool active,Func<bool>? stillCurrent=null,AhaKey.Integrations.AssistantProductState state=AhaKey.Integrations.AssistantProductState.Working)
    {
        if(manager.RealDevice?.Observation is not {IsLive:true,SessionId:{} session,Status:{} status} || status.WorkMode!=(byte)profile)return;
        byte code=active?(byte)1:(byte)0;
        if(preferences.Settings.AdvancedLightingMapping)
        {var ev=state switch{AhaKey.Integrations.AssistantProductState.Error=>IdeEventState.Notification,AhaKey.Integrations.AssistantProductState.NeedsAttention=>IdeEventState.PermissionRequest,AhaKey.Integrations.AssistantProductState.Working=>IdeEventState.PreToolUse,AhaKey.Integrations.AssistantProductState.Done=>IdeEventState.TaskCompleted,_=>IdeEventState.Stop};code=manager.Tracker.Draft.Profiles[profile].Lighting.Mapping.GetValueOrDefault(ev);}
        if(lastFeedback is {} last && last.Session==session && last.Profile==profile && last.Code==code)return;
        if(failedFeedbackSession==session || stillCurrent?.Invoke()==false)return;
        if(!active && (lastFeedback is null || lastFeedback.Value.Session!=session || lastFeedback.Value.Profile!=profile))return;
        if(!Features.CanUseRuntimeLighting(code).Available || active && (owner is null||!FeedbackOperational(profile,owner)))return;
        try
        {
            bool sent=await manager.ExecuteFeedbackAsync(ApprovedControlPlan.RuntimeEffect(session,"Aggregated assistant state; explicit feedback opt-in",code),profile,
                ()=>(stillCurrent?.Invoke()??true)&&(active?owner is not null&&FeedbackOperational(profile,owner):lastFeedback?.Session==session&&lastFeedback?.Profile==profile),
                ()=>{Intent(new{Operation="Aggregate feedback",Session=session,Profile=profile,Effect=code,At=DateTimeOffset.UtcNow});Interlocked.Increment(ref aggregateOperations);},Record);
            if(sent){lastFeedback=(session,profile,code);Interlocked.Increment(ref aggregateSuccess);FeedbackObserved?.Invoke(new(session,profile,owner??"Coordinator",active?IdeEventState.PreToolUse:IdeEventState.Stop,"AggregatedState"),new(FeedbackDisposition.Accepted,code));}
        }
        catch(Exception ex)when(ex is not OutOfMemoryException){failedFeedbackSession=session;LastError="PhysicalFeedbackStopped";}
        Changed?.Invoke();
    }
}

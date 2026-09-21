using System.Windows;
using System.IO;
using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Protocol;
using AhaKey.Integrations;
using AhaKey.Services;
using AhaKey.Studio.Services;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
namespace AhaKey.Studio.ViewModels;
public sealed record EffectChoice(byte Code,string Name);
public sealed class LightingEventRow(IdeEventState ev,ControlsViewModel owner):ObservableObject
{
    public string Name=>owner.L[ev.ToString()];
    public IdeEventState Event=>ev;
    public IReadOnlyList<EffectChoice> Effects=>owner.Effects;
    public bool Enabled=>owner.CanPreview&&owner.AdvancedMapping&&owner.HasIntegrations;
    public EffectChoice? Selected {get=>Effects.FirstOrDefault(x=>x.Code==owner.Mapping(ev));set{if(value is not null&&value.Code!=owner.Mapping(ev))owner.Map(ev,value.Code);OnPropertyChanged();}}
    public RelayCommand PreviewCommand=>new(()=>owner.Preview(Selected?.Code??0),()=>Enabled);
    public string PreviewLabel=>owner.L["PhysicalPreview"];
    public void Refresh(){OnPropertyChanged(string.Empty);}
}
public sealed class ControlsViewModel:ObservableObject
{
    private readonly DeviceManager manager;private readonly ProfilesViewModel profiles;private readonly PhysicalControlRuntime runtime;private readonly ProfileSelectionService preferences;
    private bool busy;private string integration="Codex";private string? message;
    public LocalizationService L {get;}
    public IReadOnlyList<LightingEventRow> Events {get;}
    private readonly IntegrationRuntime? integrations;
    private string[] configuredIntegrations=[];
    public IReadOnlyList<string> Integrations=>configuredIntegrations;
    public bool HasIntegrations=>Integrations.Count>0;
    public bool NoIntegrations=>!HasIntegrations;
    public event Action? SetupRequested;
    public RelayCommand ConfigureIntegrationsCommand {get;}
    public string IntegrationStatus=>integrations?.Manager.Statuses.FirstOrDefault(s=>s.Id.ToString()==integration) is {} status?$"{integration} · {L[status.Ready?"ProductReady":"ProductCheckDetails"]} · {L[status.ServiceRunning?"IntegrationServiceRunning":"IntegrationServiceStopped"]}\n{L["IntegrationLastActivity"]}: {status.LastActivity?.ToLocalTime().ToString("HH:mm:ss")??L["IntegrationNoActivity"]}":L["IntegrationSetupHint"];
    private EffectChoice[] effectChoices=[];private string effectSignature="";
    private static readonly string[] effectKeys=["Off","SingleMove","RainbowMove","RainbowWave","RainbowWaveSlow","Breathing","MiddleLight","TypingRipple","Comet","ScanBar","PulseCenter","WarningBlink","SuccessSweep","BlueThinking","LowBattery","ChargingFlow","ApprovalWait"];
    private int brightnessValue=35;private bool brightnessDirty;private DateTimeOffset? brightnessStatusAt;
    public int BrightnessValue {get=>brightnessValue;set{int next=Math.Clamp(value,1,100);if(next==brightnessValue)return;brightnessValue=next;brightnessDirty=true;OnPropertyChanged();OnPropertyChanged(nameof(BrightnessDirty));ApplyBrightnessCommand.NotifyCanExecuteChanged();}}
    public bool BrightnessDirty=>brightnessDirty;
    public bool CanConfigureLighting=>manager.RealDevice?.Observation.IsLive==true&&manager.RealDevice.ActiveTransport==PhysicalTransportKind.Usb&&runtime.Features.CanSetBrightness().Available&&!busy;
    public AsyncRelayCommand ApplyBrightnessCommand {get;}
    public AsyncRelayCommand ApplyMappingCommand {get;}
    public AsyncRelayCommand StopPreviewCommand {get;}

    public string Integration {get=>integration;set{if(SetProperty(ref integration,value))Refresh();}}
    public HardwareProfileId? Profile=>profiles.Selected?.Profile.HardwareProfileId;
    public string ProfileName=>profiles.Selected?.Name??L["ChooseProfile"];
    public string FeedbackDiagnostics=>$"{L["FeedbackReceived"]}: {runtime.ReceivedEvents} · {L["FeedbackDuplicates"]}: {runtime.SuppressedDuplicates} · {L["FeedbackOperations"]}: {runtime.FeedbackOperations} ({L["FeedbackAcked"]}: {runtime.AcceptedFeedbackOperations})";
    public IReadOnlyList<EffectChoice> Effects
    {get{var codes=(runtime.Effects.Count==0?new byte[]{0,1}:runtime.Effects.Order().ToArray());var signature=string.Join(",",codes)+L["EffectOff"];if(signature!=effectSignature){effectSignature=signature;effectChoices=codes.Select(c=>new EffectChoice(c,L["Effect"+effectKeys[c]])).ToArray();}return effectChoices;}}


    private byte previewCode=1;
    public EffectChoice? SelectedEffect {get=>Effects.FirstOrDefault(e=>e.Code==previewCode);set{if(value is not null){previewCode=value.Code;OnPropertyChanged();}}}
    public RelayCommand PreviewCommand {get;}
    public bool CanPreview=>!busy && !runtime.UsbOperationBusy && Profile is not null && runtime.Effects.Contains(0) && runtime.Effects.Contains(1);
    public bool AdvancedMapping {get=>preferences.Settings.AdvancedLightingMapping;set{if(value==AdvancedMapping)return;try{preferences.Update(s=>s with{AdvancedLightingMapping=value});}catch(Exception ex)when(ex is not OutOfMemoryException){message="SettingsSaveError";}Refresh();}}
    public string FeedbackStateKey(HardwareProfileId profile,string integration)=>runtime.FeedbackStateKey(profile,integration);
    public string FeedbackState=>L[Profile is {} p?FeedbackStateKey(p,Integration):"ProductOff"];
    public bool CanEnableFeedback=>HasIntegrations&&!runtime.UsbOperationBusy && Profile is not null && (FeedbackEnabled || runtime.FeedbackAvailable);
    public bool NeedsUsb=>manager.RealDevice?.Observation.IsLive!=true || manager.RealDevice?.ActiveTransport!=PhysicalTransportKind.Usb&&!runtime.FeedbackAvailable;
    public AsyncRelayCommand ConnectUsbCommand {get;}
    public bool FeedbackEnabled {get=>Profile is {} p && runtime.FeedbackEnabled(p,Integration);set{if(value==FeedbackEnabled)return;message=null;if(value && !runtime.FeedbackAvailable){message="ProductConnectUsbLighting";Refresh();return;}try{if(Profile is {} p)runtime.EnableFeedback(p,Integration,value);}catch(Exception ex)when(ex is not OutOfMemoryException){message="SettingsSaveError";}Refresh();}}
    public string Brightness=>manager.RealDevice?.Observation is {IsLive:true,Status:{} s} && s.Brightness is {} b?$"{b}%":L["PhysicalNotReported"];
    public string Gate=>L[NeedsUsb?"ProductConnectUsbLighting":"LightingRuntimeAccepted"];
    public string? Message=>runtime.LastError is {} error?L[error]:message is null?null:L[message];
    internal void PreviewAccepted(){message="PhysicalWriteAccepted";Refresh();}
    public ControlsViewModel(DeviceManager manager,ProfilesViewModel profiles,PhysicalControlRuntime runtime,LocalizationService l,ProfileSelectionService preferences,IntegrationRuntime? integrations=null)
    {this.integrations=integrations;if(integrations is not null)integrations.Manager.Changed+=Refresh;ConfigureIntegrationsCommand=new(()=>SetupRequested?.Invoke());ApplyBrightnessCommand=new(ApplyBrightnessAsync,()=>CanConfigureLighting&&brightnessDirty);ApplyMappingCommand=new(ApplyMappingAsync,()=>CanConfigureLighting&&AdvancedMapping&&HasIntegrations);StopPreviewCommand=new(()=>PreviewOperationAsync(0),()=>CanPreview);this.preferences=preferences;this.manager=manager;this.profiles=profiles;this.runtime=runtime;L=l;ConnectUsbCommand=new(async()=>{message=null;try{await runtime.ConnectFeedbackUsbAsync();}catch(ProductRouteException ex){message=ex.Key;}catch(Exception ex)when(ex is not OutOfMemoryException){message="ProductUsbConnectFailed";}Refresh();},()=>!runtime.UsbOperationBusy);PreviewCommand=new(()=>Preview(previewCode),()=>CanPreview);Events=Enum.GetValues<IdeEventState>().Select(x=>new LightingEventRow(x,this)).ToArray();manager.Changed+=Refresh;profiles.PropertyChanged+=(_,_)=>Refresh();runtime.Changed+=Refresh;l.PropertyChanged+=(_,_)=>Refresh();}
    public byte Mapping(IdeEventState ev)=>Profile is {} p?manager.Tracker.Draft.Profiles[p].Lighting.Mapping.GetValueOrDefault(ev):(byte)0;
    public void Map(IdeEventState ev,byte code)
    {if(Profile is not {} p || !runtime.Effects.Contains(code))return;var draft=manager.Tracker.Draft;var profile=draft.Profiles[p];manager.Edit(draft with{Profiles=draft.Profiles.SetItem(p,profile with{Lighting=profile.Lighting with{Mapping=profile.Lighting.Mapping.SetItem(ev,code)}})});}
    public async void Preview(byte code)
    {
        if(!CanPreview)return;

        busy=true;Refresh();
        try{await runtime.PreviewAsync(code,"User approved exact runtime preview and neutral off");PreviewAccepted();}
        catch(Exception ex)when(ex is not OutOfMemoryException){message="PhysicalIndeterminate";}
        finally{busy=false;Refresh();}
    }
    private async Task PreviewOperationAsync(byte code)
    {if(!CanPreview)return;busy=true;Refresh();try{await runtime.PreviewAsync(code,"User selected runtime preview/off");}catch(Exception ex)when(ex is not OutOfMemoryException){message="PhysicalIndeterminate";}finally{busy=false;Refresh();}}
    private async Task ApplyBrightnessAsync()
    {
        if(!CanConfigureLighting||manager.RealDevice?.Observation.SessionId is not {} session)return;byte value=(byte)brightnessValue;busy=true;Refresh();
        try{await manager.ExecuteControlsAsync(ApprovedControlPlan.Brightness(session,"User applied persistent brightness; global save",value),runtime.Record);
            var read=await manager.ReadConfigAsync(2,0,runtime.Record);if(read[0]!=value)throw new IOException("Brightness readback mismatch.");brightnessDirty=false;message="PhysicalWriteAccepted";}
        catch(Exception ex)when(ex is not OutOfMemoryException){message="PhysicalIndeterminate";CrashEvidence.Record(ex,"Brightness stopped");}finally{busy=false;Refresh();}
    }
    private async Task ApplyMappingAsync()
    {
        if(!CanConfigureLighting||Profile is not {} profile||manager.RealDevice?.Observation.SessionId is not {} session)return;
        byte[] values=Enum.GetValues<IdeEventState>().Select(Mapping).ToArray();busy=true;Refresh();
        try{await manager.ExecuteControlsAsync(ApprovedControlPlan.LightingMap(session,"User applied event mapping; global save",profile,values),runtime.Record);
            var read=await manager.ReadConfigAsync(1,(byte)profile,runtime.Record);if(!read.SequenceEqual(values))throw new IOException("Lighting map readback mismatch.");message="PhysicalWriteAccepted";}
        catch(Exception ex)when(ex is not OutOfMemoryException){message="PhysicalIndeterminate";CrashEvidence.Record(ex,"Lighting map stopped");}finally{busy=false;Refresh();}
    }
    public void Refresh()
    {if(Application.Current is {} app&&!app.Dispatcher.CheckAccess()){app.Dispatcher.BeginInvoke(Refresh);return;}if(!brightnessDirty&&manager.RealDevice?.Observation is {StatusAt:{} at,Status:{Brightness:{} b}}&&brightnessStatusAt!=at){brightnessValue=b;brightnessStatusAt=at;}
        var available=integrations?.Manager.Statuses.Where(x=>x.Configured==EvidenceState.Yes&&x.Compatible!=EvidenceState.No&&x.Id!=AssistantId.Kimi).Select(x=>x.Id.ToString()).ToArray()??["Codex"];
        if(!configuredIntegrations.SequenceEqual(available)){configuredIntegrations=available;if(!available.Contains(integration))integration=available.FirstOrDefault()??"";}
        OnPropertyChanged(string.Empty);ApplyBrightnessCommand.NotifyCanExecuteChanged();ApplyMappingCommand.NotifyCanExecuteChanged();StopPreviewCommand.NotifyCanExecuteChanged();PreviewCommand.NotifyCanExecuteChanged();ConnectUsbCommand.NotifyCanExecuteChanged();foreach(var row in Events)row.Refresh();}
}

using System.IO;
using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Protocol;
using AhaKey.Services;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using AhaKey.Studio.Services;
using System.Windows;
namespace AhaKey.Studio.ViewModels;
public sealed class ManualModifier(ShortcutModifiers flag,string name,KeymapViewModel owner):ObservableObject
{
    public ShortcutModifiers Flag=>flag;
    public string Name=>name;
    public bool IsSelected {get=>owner.ManualModifiers.HasFlag(flag);set=>owner.SetManualModifier(flag,value);}
    public void Refresh()=>OnPropertyChanged(nameof(IsSelected));
}
public sealed class KeyRegionViewModel(PhysicalKey key, KeymapViewModel owner) : ObservableObject
{
    public PhysicalKey Key => key;
    public string Name => key.ToString();
    public double X => Controls.DevicePreview.Regions[(int)key].Bounds.X;
    public double Y => Controls.DevicePreview.Regions[(int)key].Bounds.Y;
    public double Width => Controls.DevicePreview.Regions[(int)key].Bounds.Width;
    public double Height => Controls.DevicePreview.Regions[(int)key].Bounds.Height;
    public string Description => owner.RegionDescription(key);
    public void Refresh() => OnPropertyChanged(nameof(Description));
}
public sealed class KeymapViewModel : ObservableObject
{
    private readonly DeviceManager manager;
    private readonly ProfilesViewModel profiles;
    private readonly ProfileSelectionService preferences;
    private string? feedbackKey;
    private KeyAction? testedAction;
    private bool advanced;
    public IReadOnlyList<string> ManualKeys {get;}=ShortcutGesture.Keys.OrderBy(p=>p.Value).Select(p=>p.Key).ToArray();
    public IReadOnlyList<ManualModifier> LeftModifiers {get;}
    public IReadOnlyList<ManualModifier> RightModifiers {get;}
    public ShortcutModifiers ManualModifiers=>Session.Action is KeyboardShortcutAction a && ShortcutGesture.TryParse(a.Shortcut,out var g)?g!.Modifiers:ShortcutModifiers.None;
    public string? ManualKey
    {
        get=>Session.Action is KeyboardShortcutAction a && ShortcutGesture.TryParse(a.Shortcut,out var g)?g!.Key:null;
        set{if(!Editable || value is null || value==ManualKey || !ShortcutGesture.Keys.ContainsKey(value))return;CancelCapture();Session.SetShortcut(new(ManualModifiers,value));feedbackKey=null;testedAction=null;Refresh();}
    }
    public void SetManualModifier(ShortcutModifiers flag,bool enabled)
    {
        if(!Editable||ManualModifiers.HasFlag(flag)==enabled)return;var modifiers=enabled?ManualModifiers|flag:ManualModifiers&~flag;
        CancelCapture();Session.SetShortcut(new(modifiers,ManualKey??"Enter"));feedbackKey=null;testedAction=null;Refresh();
    }
    private readonly PhysicalControlRuntime physical;
    private readonly ProductWriteHistory history;private readonly ProductDialogs dialogs;
    private readonly LocalDeviceProjectStore projects;
    public IReadOnlyList<string> Presets {get;}=["Ctrl+Enter","Enter","Escape","Backspace","Ctrl+Y","Ctrl+N"];
    public string SelectedPreset {get;set;}="Ctrl+Enter";
    public IReadOnlyList<ProfileCardViewModel> CopyProfiles=>profiles.Cards;
    private ProfileCardViewModel? copyProfile;
    public ProfileCardViewModel CopyProfile {get=>copyProfile??profiles.Cards[3];set=>SetProperty(ref copyProfile,value);}
    public RelayCommand ApplyPresetCommand {get;}
    public RelayCommand CopyFromProfileCommand {get;}
    public RelayCommand CopyKeyToProfileCommand {get;}
    public RelayCommand UndoCommand {get;}
    public string ChangedKeys {get{var keys=Enumerable.Range(1,3).Select(i=>(PhysicalKey)i).Where(k=>!MatchesLocalBaseline(k)).ToArray();return keys.Length==0?L["NoLocalKeyChanges"]:L["ChangedKeys"]+": "+string.Join(", ",keys);}}
    public RelayCommand TestPhysicalCommand {get;}
    public AsyncRelayCommand ReadPhysicalCommand {get;}
    public event Action? CaptureRequested;
    public event Action? VoiceRequested;
    public event Action<bool>? KeyTestActive;
    public RelayCommand VoiceCommand {get;}
    public string VoiceActionLabel=>L[projects.Current?.Voice is {Enabled:true,Action:not VoiceHostAction.None}?"TestAction":"VoiceSetup"];
    private readonly Dictionary<(Guid,HardwareProfileId,PhysicalKey),(string Value,DateTimeOffset At)> readValues=new();
    public string ReadbackText=>manager.RealDevice?.Observation.SessionId is {} id&&readValues.TryGetValue((id,Session.Profile,Session.Key),out var value)?$"{L["KeyReadObservation"]}: {value.Value} · {value.At.ToLocalTime():HH:mm:ss} · {L["PartialKeyRead"]}":L["KeyNotRead"];
    private bool CanReadPhysical=>manager.RealDevice?.Observation.IsLive==true&&manager.RealDevice.ActiveTransport==PhysicalTransportKind.Usb&&physical.Features.CanReadConfigResource(0).Available;
    private readonly Dictionary<(Guid,HardwareProfileId,PhysicalKey),PhysicalKeyValue> accepted=new();
    private string physicalState="PhysicalLocalOnly";
    private KeyWritePlan? statePlan;
    private Guid? stateSession;
    public bool IsReal=>manager.RealBackendSelected;
    private ProductWriteReceipt? Receipt(PhysicalKey key,HardwareProfileId? profile=null)
    {
        var id=profile??Session.Profile;var config=manager.Tracker.Draft.Profiles[id];
        return config.Keys[key] is KeyboardShortcutAction a ? history.Find(PhysicalControlRuntime.DeviceHash(manager.RealDevice),manager.RealDevice?.Identity.Firmware??"",$"Key:{(int)id}:{(int)key}",ProductWriteHistory.KeyHash(a.Shortcut,config.DeviceLabels.GetValueOrDefault(key,""))) : null;
    }
    private ProductWriteReceipt? UsbReceipt(PhysicalKey key,HardwareProfileId? profile=null)
    {
        var id=profile??Session.Profile;var config=manager.Tracker.Draft.Profiles[id];var proof=physical.StoredUsbAcceptance;
        if(manager.RealDevice?.Observation.IsLive==true && manager.RealDevice.FirmwareIdentity.ReportedVersion!=proof?.Firmware)return null;
        return proof?.KeyBehaviorVerified==true && config.Keys[key] is KeyboardShortcutAction a ? history.Find(proof.DeviceHash,proof.Firmware,$"Key:{(int)id}:{(int)key}",ProductWriteHistory.KeyHash(a.Shortcut,config.DeviceLabels.GetValueOrDefault(key,""))):null;
    }
    private bool MatchesLocalBaseline(PhysicalKey key,HardwareProfileId? profile=null)
    {
        var id=profile??Session.Profile;var config=manager.Tracker.Draft.Profiles[id];
        return config.Keys[key] is KeyboardShortcutAction a && history.HasMatchingLocalValue($"Key:{(int)id}:{(int)key}",ProductWriteHistory.KeyHash(a.Shortcut,config.DeviceLabels.GetValueOrDefault(key,"")));
    }
    public string SummaryState => L[Enumerable.Range(1,3).All(i=>Receipt((PhysicalKey)i) is not null)?"PhysicalWriteAccepted":Enumerable.Range(1,3).All(i=>UsbReceipt((PhysicalKey)i) is not null)?"ProductWrittenUsb":Enumerable.Range(1,3).All(i=>MatchesLocalBaseline((PhysicalKey)i))?"ProductWriteStatusUnavailable":"PhysicalLocalOnly"];
    public string PhysicalState
    {
        get
        {
            if(statePlan is not null && (stateSession==manager.RealDevice?.Observation.SessionId || physicalState=="PhysicalIndeterminate") && statePlan.Profile==Session.Profile && statePlan.Key==Session.Key && statePlan.Value.Label==Session.DeviceLabel && Session.Action is KeyboardShortcutAction a && a.Shortcut==statePlan.Value.Shortcut.Canonical)return L[physicalState];
            string target=$"Key:{(int)Session.Profile}:{(int)Session.Key}";
            if(Session.Action is KeyboardShortcutAction local && projects.Current?.KeyWriteAttempts.GetValueOrDefault(target) is {} attempt && attempt.ValueHash==ProductWriteHistory.KeyHash(local.Shortcut,Session.DeviceLabel))
            {
                if(attempt.State==KeyWriteProvenance.OutcomeUncertain)return L["PhysicalIndeterminate"];
                if(attempt.State==KeyWriteProvenance.SendFailed)return L["PhysicalSendFailed"];
                if(attempt.State==KeyWriteProvenance.Sending)return L["PhysicalPendingWrite"];
            }
            var receipt=Receipt(Session.Key);return L[receipt is null?(UsbReceipt(Session.Key) is not null?"ProductWrittenUsb":MatchesLocalBaseline(Session.Key)?"ProductWriteStatusUnavailable":"PhysicalLocalOnly"):receipt.BehaviorVerified?"PhysicalBehaviorVerified":"PhysicalWriteAccepted"];
        }
    }
    private bool PhysicalEligibility=>manager.RealBackendSelected && Editable && !LabelInvalid && Session.Action is KeyboardShortcutAction a && ShortcutGesture.TryParse(a.Shortcut,out _);
    public bool CanWritePhysical=>PhysicalEligibility && !PhysicalWriteCommand.IsRunning && !physical.UsbOperationBusy;
    public AsyncRelayCommand PhysicalWriteCommand {get;}
    public LocalizationService L { get; }
    public KeymapSession Session { get; }
    public ShortcutCapture Capture { get; } = new();
    public IReadOnlyList<KeyRegionViewModel> Keys { get; }
    public KeyRegionViewModel SelectedKey { get => Keys[(int)Session.Key]; set { if(value is null || value.Key==Session.Key) return; CancelCapture(); Session.SelectKey(value.Key); testedAction=null; feedbackKey=null; Refresh(); } }
    public bool HasProfile => profiles.HasSelection;
    public bool IsK1 => Session.Key==PhysicalKey.K1;
    public bool Editable => HasProfile && !IsK1;
    public string ProfileName => profiles.Selected?.Name ?? L["ChooseProfile"];
    public string KeyTitle => $"{Session.Key} · {L[IsK1 ? "VoiceRole" : "KeyboardShortcut"]}";
    public string ActionText => Describe(Session.Action);
    public string[] Chips => Session.Action is KeyboardShortcutAction a && ShortcutGesture.TryParse(a.Shortcut,out var g) ? g!.Canonical.Split('+') : IsK1 ? ["F18"] : [];
    public bool HasShortcut => Chips.Length>0;
    public bool NoShortcut => !HasShortcut;
    public string LocalName
    {
        get => preferences.LocalKeyName(Session.Profile,Session.Key);
        set { if(value==LocalName)return;try { preferences.Update(s=>s with { KeyLocalNames=s.KeyLocalNames.SetItem(LocalId(Session.Key),value) }); feedbackKey=null; } catch(Exception ex) when(ex is IOException or UnauthorizedAccessException or ArgumentException) { feedbackKey="SettingsSaveError"; } Refresh(); }
    }
    public string DeviceLabel { get => Session.DeviceLabel; set { if(value==Session.DeviceLabel)return;Session.SetDeviceLabel(value); testedAction=null; Refresh(); } }
    public bool LabelInvalid => !Session.IsLabelValid;
    public bool HasInvalidLabels => Session.HasInvalidLabels;
    public bool IsRecording => Capture.IsRecording;
    public bool NotRecording => !IsRecording;
    public string CaptureModifiers => string.Join(" + ",ShortcutGesture.ModifierOrder.Where(x=>Capture.Modifiers.HasFlag(x.Flag)).Select(x=>x.Name));
    public bool Advanced { get=>advanced; set=>SetProperty(ref advanced,value); }
    public string DiagnosticText
    {
        get
        {
            var s=$"{L["HardwareProfileId"]}: {(int)Session.Profile}\n{L["PhysicalKeyIndex"]}: {Session.Key} / {(int)Session.Key}\n{L["ActionType"]}: {Session.Action.GetType().Name}";
            if(IsK1) return s+"\nHID: 6D (F18)\n"+L["K1Evidence"];
            if(Session.Action is KeyboardShortcutAction a && ShortcutGesture.TryParse(a.Shortcut,out var g)) s+=$"\nHID: {Convert.ToHexString(g!.HidSequence).ChunkText()}\n{L["EncodedPreview"]}: {Convert.ToHexString(ShortcutDiagnostics.Preview(Session.Profile,Session.Key,a)).ChunkText()}";
            return s+"\n"+L["EncodingEvidence"];
        }
    }
    public string? Feedback => (physical.RouteNotice??(PhysicalState==L["PhysicalIndeterminate"]?"PhysicalIndeterminate":feedbackKey)) is {} notice ? L[notice] : testedAction is not null ? $"{L["WouldSend"]} {Describe(testedAction)} · {L["Simulation"]}" : null;
    public bool HasFeedback => Feedback is not null;
    public string Provenance=>L[manager.RealBackendSelected?(physical.KeyAvailable?"PhysicalKeyAvailable":"PhysicalKeyGate"):"SimulatorConfiguration"];
    public string ProfileState => manager.RealBackendSelected?SummaryState:L[Session.IsDirty(Session.Profile)?"UnsavedChanges":manager.Tracker.State.ToString()];
    public bool IsMock=>!manager.RealBackendSelected;
    public string EditorMode=>L[IsMock?"Simulation":"BleLocalDraft"];
    public string CaptureHint=>L[IsMock?"CaptureHint":"BleCaptureHint"];
    public bool CanTest => HasProfile && !manager.RealBackendSelected && manager.Device is IActionSimulator && !LabelInvalid;
    public RelayCommand RecordCommand { get; }
    public RelayCommand CancelCommand { get; }
    public RelayCommand ClearCommand { get; }
    public RelayCommand ResetCommand { get; }
    public RelayCommand TestCommand { get; }
    public KeymapViewModel(DeviceManager manager,ProfilesViewModel profiles,ProfileSelectionService preferences,LocalizationService l,PhysicalControlRuntime physical,ProductWriteHistory history,ProductDialogs dialogs,LocalDeviceProjectStore projects)
    {
        this.dialogs=dialogs;this.history=history;TestPhysicalCommand=new(TestPhysical,()=>CanTestPhysical);this.physical=physical;PhysicalWriteCommand=new(WritePhysicalAsync,()=>CanWritePhysical);PhysicalWriteCommand.PropertyChanged+=(_,e)=>{if(e.PropertyName==nameof(AsyncRelayCommand.IsRunning))Refresh();};
        this.manager=manager; this.profiles=profiles; this.preferences=preferences; L=l; Session=new(manager);
        this.projects=projects;
        ReadPhysicalCommand=new(ReadPhysicalAsync,()=>CanReadPhysical);VoiceCommand=new(()=>VoiceRequested?.Invoke());
        ApplyPresetCommand=new(()=>{if(ShortcutGesture.TryParse(SelectedPreset,out var gesture))Session.SetShortcut(gesture!);Refresh();},()=>Editable);
        CopyFromProfileCommand=new(()=>{Session.CopyFromProfile(CopyProfile.Profile.HardwareProfileId);Refresh();},()=>HasProfile);
        CopyKeyToProfileCommand=new(()=>{Session.CopyKeyToProfile(CopyProfile.Profile.HardwareProfileId);Refresh();},()=>Editable&&!LabelInvalid);
        UndoCommand=new(()=>{CancelCapture();Session.Undo();Refresh();},()=>Session.CanUndo);
        LeftModifiers=ShortcutGesture.ModifierOrder.Where(x=>!x.Name.StartsWith("Right")).Select(x=>new ManualModifier(x.Flag,x.Name,this)).ToArray();
        RightModifiers=ShortcutGesture.ModifierOrder.Where(x=>x.Name.StartsWith("Right")).Select(x=>new ManualModifier(x.Flag,x.Name,this)).ToArray();
        Keys=Enum.GetValues<PhysicalKey>().Select(k=>new KeyRegionViewModel(k,this)).ToArray();
        RecordCommand=new(()=>{Capture.Start(); feedbackKey=null; testedAction=null; Refresh();CaptureRequested?.Invoke();},()=>Editable);
        CancelCommand=new(CancelCapture);
        ClearCommand=new(()=>{CancelCapture();Session.ClearForSimulation();Refresh();},()=>Editable && manager.Device.Identity.IsSimulation);
        ResetCommand=new(()=>{CancelCapture();Session.ResetKey();Refresh();},()=>Editable);
        TestCommand=new(()=>{testedAction=((IActionSimulator)manager.Device).TestAction(Session.Key,Session.Action).Action;feedbackKey=null;Refresh();},()=>CanTest);
        profiles.PropertyChanged+=(_,e)=>{ if(e.PropertyName==nameof(ProfilesViewModel.Selected)) { CancelCapture(); testedAction=null; feedbackKey=null; if(profiles.Selected is {} p) Session.Profile=p.Profile.HardwareProfileId; Refresh(); } };
        manager.Changed+=Refresh;preferences.Changed+=Refresh; L.PropertyChanged+=(_,_)=>Refresh();
        physical.Changed+=Refresh;
        if(profiles.Selected is {} selected) Session.Profile=selected.Profile.HardwareProfileId;
    }
    private async Task WritePhysicalAsync()
    {
        if(!PhysicalEligibility || Session.Action is not KeyboardShortcutAction action || !ShortcutGesture.TryParse(action.Shortcut,out var gesture))return;
        var profile=Session.Profile;var key=Session.Key;var label=Session.DeviceLabel;var profileName=ProfileName;
        feedbackKey=null;
        try {await physical.WithKeyRouteAsync(()=>WriteConnectedAsync(profile,key,new(gesture!,label),profileName));}
        catch(ProductRouteException ex){feedbackKey=ex.Key;}
        catch(Exception ex)when(ex is not OutOfMemoryException){feedbackKey="ProductUsbConnectFailed";}
        finally{Refresh();}
    }
    private async Task ReadPhysicalAsync()
    {
        if(!CanReadPhysical||manager.RealDevice?.Observation.SessionId is not {} session)return;
        var profile=Session.Profile;var key=Session.Key;
        try
        {
            var bytes=await manager.ReadConfigAsync(0,(byte)((int)profile*4+(int)key),physical.Record);
            var shortcut=KeyResource.Shortcut(bytes.AsSpan());
            var value=shortcut?.Display??L["KeyResourceOther"];
            readValues[(session,profile,key)]=(value,DateTimeOffset.UtcNow);
            await Task.Run(()=>projects.Update(p=>p with{PhysicalReadObservations=p.PhysicalReadObservations.Add(new($"Key:{(int)profile}:{(int)key}",Convert.ToHexString(bytes.AsSpan()),DateTimeOffset.UtcNow,"9D live RAM; label absent"))}));
        }
        catch(Exception ex)when(ex is not OutOfMemoryException){feedbackKey="KeyReadFailed";CrashEvidence.Record(ex,"Read key resource");}
        finally{Refresh();}
    }
    private async Task WriteConnectedAsync(HardwareProfileId profile,PhysicalKey key,PhysicalKeyValue value,string profileName)
    {
        if(!physical.Features.CanWriteShortcut(profile,key).Available || manager.RealDevice?.Observation.SessionId is not {} session)return;
        var address=(session,profile,key);
        var plan=KeyWritePlan.Create(profile,key,value,accepted.GetValueOrDefault(address));
        if(plan.Commands.IsEmpty){statePlan=plan;stateSession=session;physicalState="PhysicalNoChanges";Refresh();return;}
        string preview=$"{manager.Device.Identity.Name} · {profileName} · {key}\n{value.Shortcut.Display} · {value.Label}\n\n{L["ProductKeyConfirmation"]}";
        if(!dialogs.ConfirmKey(preview,L))return;
        string device=PhysicalControlRuntime.DeviceHash(manager.RealDevice)!;string firmware=manager.RealDevice.Identity.Firmware;
        string target=$"Key:{(int)plan.Profile}:{(int)plan.Key}";
        var verification=new PhysicalKeyVerification();verification.Begin();statePlan=plan;stateSession=session;physicalState="PhysicalPendingWrite";Refresh();
        bool attempted=false;
        string valueHash=ProductWriteHistory.KeyHash(value.Shortcut.Canonical,value.Label);
        try
        {
            projects.Update(p=>p with{KeyWriteAttempts=p.KeyWriteAttempts.SetItem(target,new(target,valueHash,DateTimeOffset.UtcNow,KeyWriteProvenance.Sending))});
            history.Forget(device,target);
            physical.Intent(new{At=DateTimeOffset.UtcNow,Session=session,Profile=plan.Profile,Key=plan.Key,Commands=plan.Commands.Select(c=>Convert.ToHexString(c.Frame.AsSpan())),Approval="User accepted exact Studio preview"});
            attempted=true;await manager.ExecuteControlsAsync(ApprovedControlPlan.Key(session,"User accepted exact Studio preview",plan),physical.Record);
            accepted[address]=plan.Value;verification.Accept(plan.Value);physicalState="PhysicalWriteAccepted";
            Session.AcceptLocalKey(profile,key,new KeyboardShortcutAction(value.Shortcut.Canonical),value.Label);
            try{projects.Update(p=>p with{KeyWriteAttempts=p.KeyWriteAttempts.SetItem(target,new(target,valueHash,DateTimeOffset.UtcNow,KeyWriteProvenance.SentToDevice)),LastSuccessfullySent=p.LastSuccessfullySent.SetItem(target,new(target,ProductWriteHistory.KeyHash(value.Shortcut.Canonical,value.Label),DateTimeOffset.UtcNow,KeyWriteProvenance.SentToDevice))});
            history.Record(new(device,firmware,target,ProductWriteHistory.KeyHash(plan.Value.Shortcut.Canonical,plan.Value.Label),DateTimeOffset.UtcNow));}
            catch(Exception ex)when(ex is IOException or UnauthorizedAccessException or System.Text.Json.JsonException){feedbackKey="ProductReceiptFailed";}

        }
        catch(Exception ex)when(ex is not OutOfMemoryException){accepted.Remove(address);verification.Fail();physicalState=attempted?"PhysicalIndeterminate":"PhysicalSendFailed";try{projects.Update(p=>p with{KeyWriteAttempts=p.KeyWriteAttempts.SetItem(target,new(target,valueHash,DateTimeOffset.UtcNow,attempted?KeyWriteProvenance.OutcomeUncertain:KeyWriteProvenance.SendFailed))});}catch(Exception storage)when(storage is not OutOfMemoryException){feedbackKey="ProjectSaveFailed";}}
        finally{Refresh();}
    }
    private bool CanTestPhysical=>HasProfile && (IsK1 || Session.Action is KeyboardShortcutAction);
    private void TestPhysical()
    {
        var receipt=Receipt(Session.Key)??UsbReceipt(Session.Key);
        var shortcut=IsK1?"F18":(Session.Action as KeyboardShortcutAction)?.Shortcut;
        if(shortcut is null || !ShortcutGesture.TryParse(shortcut,out var gesture))return;
        var key=Session.Key;var profile=Session.Profile;
        var verification=new PhysicalKeyVerification();verification.Begin();verification.Accept(new(gesture!,Session.DeviceLabel));
        var session=manager.RealDevice?.Observation.SessionId;
        var test=new Views.PhysicalKeyTestWindow(profile,key,gesture!,verification,L){Owner=Application.Current.MainWindow};
        test.Observed+=(observed,matched)=>
        {
            physical.Intent(new{Operation="Focused behavior test",Session=session,Profile=profile,Key=key,Observed=observed.Canonical,Matched=matched,ReadbackVerified=false});
            if(matched && receipt is not null && manager.RealDevice?.Observation is {IsLive:true} live && live.SessionId==session && live.Status?.WorkMode==(int)profile && history.Find(receipt.DeviceHash,receipt.Firmware,receipt.Target,receipt.ValueHash)?.WrittenAt==receipt.WrittenAt)
            {
                try{history.Record(receipt with{BehaviorVerified=true});statePlan=KeyWritePlan.Create(profile,key,new(gesture!,Session.DeviceLabel));stateSession=session;physicalState="PhysicalBehaviorVerified";projects.Update(p=>p with{BehaviorVerifications=p.BehaviorVerifications.Add(new(receipt.Target,receipt.ValueHash,DateTimeOffset.UtcNow))});}
                catch(Exception ex)when(ex is IOException or UnauthorizedAccessException or System.Text.Json.JsonException){feedbackKey="ProductReceiptFailed";}
            }
            Refresh();
        };test.Closed+=(_,_)=>KeyTestActive?.Invoke(false);KeyTestActive?.Invoke(true);test.Show();
    }
    public void CancelCapture() { Capture.Cancel(); OnPropertyChanged(nameof(IsRecording)); OnPropertyChanged(nameof(NotRecording)); OnPropertyChanged(nameof(CaptureModifiers)); }
    public void CaptureKey(string? key,ShortcutModifiers modifiers)
    {
        if(!IsRecording) return;
        var gesture=Capture.Press(key,modifiers);
        if(gesture is not null) { Session.SetShortcut(gesture); feedbackKey=null; testedAction=null; }
        else if(key is not null) feedbackKey="InvalidShortcut";
        Refresh();
    }
    public void Written() { testedAction=null; feedbackKey=manager.ErrorKey is null ? manager.Tracker.State==SyncState.Synced && !HasInvalidLabels?"WrittenSimulator":"WrittenOlderDraft" : null; Refresh(); }
    private string LocalId(PhysicalKey key) => $"{(int)Session.Profile}:{(int)key}";
    private string Describe(KeyAction action) => action switch { KeyboardShortcutAction a when ShortcutGesture.TryParse(a.Shortcut,out var g)=>g!.Display, VoiceInputAction=>L["VoiceRole"], DisabledAction=>L[IsMock?"NoShortcut":"BleUnsetDraft"], _=>L["FutureAction"] };
    public string RegionDescription(PhysicalKey key)
    {
        var name=preferences.LocalKeyName(Session.Profile,key);
        return string.Join(" — ", new[] {key.ToString(),name,Describe(Session.Configuration.Keys[key])}.Where(x=>x.Length>0));
    }
    public void Refresh()
    {
        if(System.Windows.Application.Current is {} app && !app.Dispatcher.CheckAccess()) { app.Dispatcher.BeginInvoke(Refresh); return; }
        foreach(var card in profiles.Cards) card.IsDirty=manager.RealBackendSelected?Enumerable.Range(1,3).Any(i=>!MatchesLocalBaseline((PhysicalKey)i,card.Profile.HardwareProfileId)):Session.IsDirty(card.Profile.HardwareProfileId);
        OnPropertyChanged(string.Empty); foreach(var key in Keys) key.Refresh();
        foreach(var modifier in LeftModifiers.Concat(RightModifiers))modifier.Refresh();
        RecordCommand.NotifyCanExecuteChanged(); ClearCommand.NotifyCanExecuteChanged(); ResetCommand.NotifyCanExecuteChanged(); TestCommand.NotifyCanExecuteChanged();
        ApplyPresetCommand.NotifyCanExecuteChanged();CopyFromProfileCommand.NotifyCanExecuteChanged();CopyKeyToProfileCommand.NotifyCanExecuteChanged();UndoCommand.NotifyCanExecuteChanged();
        PhysicalWriteCommand.NotifyCanExecuteChanged();TestPhysicalCommand.NotifyCanExecuteChanged();ReadPhysicalCommand.NotifyCanExecuteChanged();
    }
}
internal static class HexDisplay { public static string ChunkText(this string value) => string.Join(" ",Enumerable.Range(0,value.Length/2).Select(i=>value.Substring(i*2,2))); }

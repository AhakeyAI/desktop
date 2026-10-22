using AhaKey.Core;
using AhaKey.Services;
using AhaKey.Studio.Services;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using System.Windows;
namespace AhaKey.Studio.ViewModels;
public sealed class ProjectViewModel:ObservableObject
{
    private readonly LocalProjectRuntime runtime;private readonly LocalDeviceProjectStore store;private readonly VoiceRoutingRuntime voice;
    public LocalizationService L {get;}
    private string? notice;
    private string? voiceNotice;
    public bool VoiceConfigured=>store.Current?.Voice is {Enabled:true,Action:not VoiceHostAction.None};
    public void TestVoiceAction()=>voice.TestAction();
    public void SuspendVoice(bool value)=>voice.Suspend(value);
    public bool VoiceNeedsShortcut=>store.Current?.Voice.Action==VoiceHostAction.LocalShortcut;
    public bool VoiceNeedsApplication=>store.Current?.Voice.Action==VoiceHostAction.ActivateApplication;
    public string? VoiceValidation=>voiceNotice is {} key?L[key]:null;
    public string? ErrorKey=>runtime.ErrorKey??store.ErrorKey;
    public string? Notice=>(notice??ErrorKey) is {} key?L[key]:null;
    public string Name=>store.Current?.Name??"";
    public IReadOnlyList<ChoiceOption<VoiceHostAction>> VoiceActions {get;}
    public ChoiceOption<VoiceHostAction> VoiceAction {get=>VoiceActions.Single(x=>x.Value==(store.Current?.Voice.Action??VoiceHostAction.None));set{if(value is not null&&value.Value!=VoiceAction.Value)UpdateVoice(v=>v with{Action=value.Value});}}
    public bool VoiceEnabled {get=>store.Current?.Voice.Enabled??false;set=>UpdateVoice(v=>v with{Enabled=value});}
    public string VoiceShortcut {get=>store.Current?.Voice.Shortcut??"";set{if(value.Length==0||ShortcutGesture.TryParse(value,out var g)&&g!.Key!="F18")UpdateVoice(v=>v with{Shortcut=value.Length==0?null:value});else{voiceNotice="InvalidShortcut";Refresh();}}}
    public string VoiceApplication=>store.Current?.Voice.ApplicationPath??L["VoiceNoApplication"];
    public string VoiceStatus=>voice.ErrorKey is {} error?L[error]:voice.LastDetectedAt is {} at?$"F18 · {at.ToLocalTime():HH:mm:ss}":L["VoiceRoutingHint"];
    public RelayCommand ExportCommand {get;}public RelayCommand ImportCommand {get;}public RelayCommand ChooseVoiceApplicationCommand {get;}
    public ProjectViewModel(LocalProjectRuntime runtime,LocalDeviceProjectStore store,LocalizationService l,VoiceRoutingRuntime voice)
    {
        this.runtime=runtime;this.store=store;this.voice=voice;L=l;
        VoiceActions=Enum.GetValues<VoiceHostAction>().Select(x=>new ChoiceOption<VoiceHostAction>(x,"VoiceAction"+x,l)).ToArray();
        ExportCommand=new(()=>{var d=new SaveFileDialog{Filter="Studio project|*.ahakey.json",FileName="my-studio.ahakey.json"};if(d.ShowDialog()==true)Try(()=>store.Export(d.FileName),"ProjectExported");});
        ImportCommand=new(()=>{var d=new OpenFileDialog{Filter="Studio project|*.ahakey.json;*.json"};if(d.ShowDialog()!=true)return;Try(()=>{var p=store.PreviewImport(d.FileName);if(MessageBox.Show(L["ProjectImportConfirm"],L["ProjectImport"],MessageBoxButton.OKCancel,MessageBoxImage.Question)==MessageBoxResult.OK){runtime.Import(p);notice="ProjectImported";}},null,true);});
        ChooseVoiceApplicationCommand=new(()=>{var d=new OpenFileDialog{Filter="Application|*.exe"};if(d.ShowDialog()==true)UpdateVoice(v=>v with{ApplicationPath=d.FileName});});
        store.Changed+=Refresh;voice.Changed+=Refresh;l.PropertyChanged+=(_,_)=>Refresh();
    }
    private void UpdateVoice(Func<VoiceRoutingSettings,VoiceRoutingSettings> change){voiceNotice=null;Try(()=>store.Update(p=>p with{Voice=change(p.Voice)}),null);}
    private void Try(Action action,string? success,bool preserveNotice=false){try{action();if(!preserveNotice)notice=success;}catch(Exception ex)when(ex is not OutOfMemoryException){notice="ProjectOperationFailed";}Refresh();}
    private void Refresh(){if(Application.Current is {} app&&!app.Dispatcher.CheckAccess()){app.Dispatcher.BeginInvoke(Refresh);return;}OnPropertyChanged(string.Empty);}
}

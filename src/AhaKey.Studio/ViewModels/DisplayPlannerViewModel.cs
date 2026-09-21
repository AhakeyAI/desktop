using System.IO;
using System.Collections.Immutable;
using System.Text.Json;
using System.Windows.Media.Imaging;
using AhaKey.Core;
using AhaKey.Protocol;
using AhaKey.Services;
using AhaKey.Studio.Services;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using System.Windows;
namespace AhaKey.Studio.ViewModels;
public sealed class DisplayPlannerViewModel:ObservableObject
{
    private readonly ProfilesViewModel profiles;private PreparedDisplayImage? prepared;private string? path;private string? error;
    private readonly PhysicalControlRuntime physical;
    private readonly AhaKey.Device.DeviceManager manager;
    private string? uploadResult;
    private readonly ProfileSelectionService preferences;private readonly SettingsStore settings;private readonly ProductWriteHistory history;private readonly ProductDialogs dialogs;
    private string? sourceName;
    private readonly LocalDeviceProjectStore projects;
    private DisplayProject? selectedProject;
    private int selectedFrame,interval=100;
    private int[] frameOrder=[];
    private string background="#000000";
    public string ProjectName {get;set;}="Display";
    private IReadOnlyList<DisplayProject> library=[];
    public IReadOnlyList<DisplayProject> Library=>library;
    private bool selectingProject;private FirmwareDialect displayedDialect;
    private CancellationTokenSource? preparing;
    public Task Preparation {get;private set;}=Task.CompletedTask;
    public bool IsPreparing {get;private set;}
    private readonly DisplayPreparationCache cache=new();
    private readonly System.Windows.Threading.DispatcherTimer animation=new();
    private BitmapSource[] previews=[];
    private IReadOnlyList<int> frames=[];
    public string CapacityText=>profiles.Selected is {} p?$"{prepared?.Frames.Count??0} / {Windows32DisplayGeometry.Capacity(asset.Value)} · 160 × 80 · RGB565":"";
    public string SourceTiming=>prepared is {} image?string.Format(L["DisplayTimingSummary"],image.SourceFrames,image.Timing.SourceDurationMs,interval,frameOrder.Length*interval):"";
    private void ReloadLibrary(){if(Application.Current is {} app&&!app.Dispatcher.CheckAccess()){app.Dispatcher.BeginInvoke(ReloadLibrary);return;}var next=projects.Current?.DisplayProjects??[];if(!library.SequenceEqual(next)){library=next.ToArray();OnPropertyChanged(nameof(Library));}Refresh();}
    public DisplayProject? SelectedProject
    {
        get=>selectedProject;
        set
        {
            if(Equals(selectedProject,value))return;
            selectedProject=value;CrashEvidence.Operation("Display selection",profiles.Selected?.Profile.HardwareProfileId,value?.Id);
            OnPropertyChanged();if(value is null)return;
            selectingProject=true;
            try{profiles.Selected=profiles.Cards[(int)value.Profile];asset=Assets.Single(x=>x.Value==value.State);sourceName=value.Name;ProjectName=value.Name;fit=FitModes.Single(x=>x.Value.ToString()==value.Fit);background=value.Background;interval=value.UniformIntervalMs;}
            finally{selectingProject=false;}
            StartPreparation(value);
        }
    }
    public string Background {get=>background;set{if(!System.Text.RegularExpressions.Regex.IsMatch(value,"^#[0-9a-fA-F]{6}$"))return;if(background==value)return;background=value;Rebuild();}}
    public int IntervalMs {get=>interval;set{var next=Math.Clamp(value,33,1000);if(next==interval)return;interval=next;animation.Interval=TimeSpan.FromMilliseconds(interval);BuildPlan();Refresh();}}
    public IReadOnlyList<int> Frames=>frames;
    public int SelectedFrame {get=>selectedFrame;set{var next=Math.Clamp(value,0,Math.Max(0,frameOrder.Length-1));if(next==selectedFrame)return;selectedFrame=next;OnPropertyChanged();OnPropertyChanged(nameof(Preview));}}
    public string TimingNotice=>L[prepared?.VariableTimingConverted==true?"DisplayUniformTimingNotice":"DisplayUniformTiming"];
    public string Duration=>$"{(prepared?.Frames.Count??0)*(StaticPlan is null?interval:100):N0} ms · {(prepared?.Frames.Count??0)*25600:N0} {L["DisplayBytes"]}";
    public string FrameOrderText=>string.Join(" → ",frameOrder.Select(x=>x+1));
    public string Progress=>$"{physical.DisplayBlocksConfirmed}/{(Modern?ModernPlan?.Transfer.Blocks.Length:7)??0} · {L["DisplayConfirmedBlocks"]}";
    public string OperationDetail
    {
        get{var record=(manager.Operations.Current is {Operation:"Display upload"} current?current:null)??manager.Operations.Journal.LastOrDefault(x=>x.Operation=="Display upload");
            return record is null?"":$"{L["Operation"+record.Outcome]} · {record.LastConfirmedStep??L["NoEvidence"]}\n{record.LastConfirmedFlashBlock??""}\n{L["DisplayBindingConfirmed"]}: {L[record.BindingChanged?"BleYes":"BleNo"]} · {L["DisplaySaveConfirmed"]}: {L[record.SaveConfirmed?"BleYes":"BleNo"]}";}
    }
    public AsyncRelayCommand SaveProjectCommand {get;}public AsyncRelayCommand DuplicateProjectCommand {get;}public AsyncRelayCommand RenameProjectCommand {get;}public RelayCommand OpenProjectCommand {get;}public RelayCommand DeleteProjectCommand {get;}public RelayCommand FrameEarlierCommand {get;}public RelayCommand FrameLaterCommand {get;}
    public event Action? ConnectionRequested;
    private string? Target=>profiles.Selected is {} p?$"{(int)p.Profile.HardwareProfileId}:{(int)asset.Value}":null;
    public string Summary(HardwareProfileId profile)
    {
        if(!preferences.Settings.DisplaySources.TryGetValue($"{(int)profile}:0",out var source))return L["ProductNotConfigured"];
        return L[source.FrameSha256 is {} hash && history.Find(PhysicalControlRuntime.DeviceHash(manager.RealDevice),manager.RealDevice?.Identity.Firmware??"",$"Display:{(int)profile}:Default",hash) is not null?"PhysicalWriteAccepted":"ProductImagePrepared"];
    }
    public string Availability=>UploadCommand.IsRunning?L["DisplayWriting"]:manager.RealDevice?.Observation.IsLive!=true?L["ProductConnectAccepted"]:IsPreparing?L["DisplayPreparing"]:CanUpload?L["ProductAvailable"]:L[Modern?(Plan is null?"DisplayImportHint":manager.RealDevice?.ActiveTransport!=AhaKey.Device.PhysicalTransportKind.Usb?"ProductRequiresUsb":"FeatureTargetUnverified"):StaticPlan is null?"ProductDisplayUnsupported":"ProductRequiresUsb"];
    public Windows32DisplayUploadPlan? ModernPlan {get;private set;}
    public StaticDisplayPlan? StaticPlan {get;private set;}
    public AsyncRelayCommand UploadCommand {get;}
    private bool Modern=>manager.RealDevice?.FirmwareIdentity.Dialect==FirmwareDialect.WindowsContract32;
    public bool CanUpload=>!IsPreparing && !UploadCommand.IsRunning && manager.RealDevice?.Observation.IsLive==true && (Modern?ModernPlan is {} p && physical.Features.CanUploadDisplay(p.Transfer.Profile,p.Transfer.Asset,p.Transfer.FrameCount).Available:StaticPlan is not null && physical.StaticDisplayAvailable && manager.RealDevice.Observation.Status?.WorkMode==2);
    public string UploadLabel=>L["DisplayUpload"];
    public string PlanHeading=>L[StaticPlan is null?"DisplayPlanDetails":"DisplayPhysicalPlanDetails"];
    public string UploadScope=>Modern?$"{ProfileName} / {L[asset.Value.ToString()]} · {CapacityText}":L["DisplayStaticScope"];
    public string? UploadResult=>uploadResult is "ProductRequiresUsb" or "ProductConnectAccepted" or "ProductActivateCodex" ? (CanUpload?null:L[uploadResult]) : uploadResult is null?null:L[uploadResult];
    private ChoiceOption<DisplayState> asset;
    private ChoiceOption<DisplayFitMode> fit;
    public IReadOnlyList<ChoiceOption<DisplayFitMode>> FitModes {get;}
    public ChoiceOption<DisplayFitMode> Fit {get=>fit;set{if(value is null||fit==value)return;fit=value;Rebuild();}}
    public string ProfileName=>profiles.Selected?.Name??L["ChooseProfile"];
    public RelayCommand ConvertCommand {get;}
    public LocalizationService L {get;}
    public IReadOnlyList<ChoiceOption<DisplayState>> Assets {get;}
    public ChoiceOption<DisplayState> Asset {get=>asset;set{if(value is null||asset==value)return;asset=value;Rebuild();}}
    public DisplayWritePlan? Plan {get;private set;}
    public BitmapSource? Preview=>frameOrder.Length>0 && selectedFrame<frameOrder.Length && frameOrder[selectedFrame]<previews.Length?previews[frameOrder[selectedFrame]]:null;
    public string Source=>sourceName??prepared?.Name??L["NoSource"];
    public string Status=>error is not null?L[error]:Plan is null?L["DisplayImportHint"]:$"{prepared!.SourceFrames} → {Plan.FrameCount} {L["DisplayFrames"]} · {(StaticPlan is null ? Plan.IntervalMs : 100)} ms · {Plan.TotalBytes:N0} bytes";
    public string PlanText=>StaticPlan is {} physicalPlan?Views.DisplayOverwriteWindow.Describe(physicalPlan,L):Plan is null?L["DisplayNoPlan"]:$"{profiles.Selected?.Name} / {(int)Plan.Profile} · {L[Plan.Asset.ToString()]}\n{L["DisplaySlots"]}: {Plan.StartSlot}–{Plan.StartSlot+Plan.FrameCount-1}\n"+
        string.Join("\n",Plan.Blocks.GroupBy(b=>b.Slot).Select(g=>$"{g.Key}: 0x{g.First().Address:X6} → 0x{g.Last().Address+g.Last().Length-1:X6} · {L["DisplaySectors"]} {g.First().Sector}–{g.Last().Sector}"))+
        $"\n82/93: {Convert.ToHexString(Plan.Binding.AsSpan()).ChunkText()}\n04: AA BB 04 CC DD\n{L["DisplayNoRollback"]}";
    public RelayCommand ImportCommand {get;}
    public RelayCommand ExportCommand {get;}
    public DisplayPlannerViewModel(ProfilesViewModel profiles,LocalizationService l,PhysicalControlRuntime physical,AhaKey.Device.DeviceManager manager,ProfileSelectionService preferences,SettingsStore settings,ProductWriteHistory history,ProductDialogs dialogs,LocalDeviceProjectStore projects)
    {this.projects=projects;
        SaveProjectCommand=new(SaveProjectAsync,()=>prepared is not null&&!IsPreparing);DuplicateProjectCommand=new(()=>EditProjectAsync(true),()=>selectedProject is not null);RenameProjectCommand=new(()=>EditProjectAsync(false),()=>selectedProject is not null);OpenProjectCommand=new(()=>{if(selectedProject is {} p)StartPreparation(p);},()=>selectedProject is not null);DeleteProjectCommand=new(()=>{if(selectedProject is {} selected)projects.Update(p=>p with{DisplayProjects=p.DisplayProjects.Remove(selected)});selectedProject=null;Refresh();});
        FrameEarlierCommand=new(()=>MoveFrame(-1));FrameLaterCommand=new(()=>MoveFrame(1));library=(projects.Current?.DisplayProjects??[]).ToArray();projects.Changed+=ReloadLibrary;animation.Interval=TimeSpan.FromMilliseconds(100);animation.Tick+=(_,_)=>{if(previews.Length>1)SelectedFrame=(selectedFrame+1)%frameOrder.Length;};
        this.dialogs=dialogs;this.preferences=preferences;this.settings=settings;this.history=history;this.profiles=profiles;this.physical=physical;this.manager=manager;L=l;UploadCommand=new(UploadAsync,()=>!IsPreparing&&(Modern?ModernPlan is not null:StaticPlan is not null));FitModes=Enum.GetValues<DisplayFitMode>().Select(x=>new ChoiceOption<DisplayFitMode>(x,"Display"+x,l)).ToArray();fit=FitModes[0];Assets=Enum.GetValues<DisplayState>().Select(x=>new ChoiceOption<DisplayState>(x,x.ToString(),l)).ToArray();asset=Assets[0];ImportCommand=new(Import,()=>profiles.HasSelection);ConvertCommand=new(Rebuild,()=>path is not null && profiles.HasSelection);ExportCommand=new(Export,()=>Plan is not null);profiles.PropertyChanged+=(_,e)=>{if(e.PropertyName==nameof(ProfilesViewModel.Selected)&&!selectingProject){selectedProject=null;RestoreSource();}};l.PropertyChanged+=(_,_)=>Refresh();manager.Changed+=DeviceChanged;physical.Changed+=Refresh;RestoreSource();}
    private void DeviceChanged()
    {
        if(Application.Current is {} app&&!app.Dispatcher.CheckAccess()){app.Dispatcher.BeginInvoke(DeviceChanged);return;}
        var dialect=manager.RealDevice?.FirmwareIdentity.Dialect??FirmwareDialect.Unknown;
        if(displayedDialect!=dialect){displayedDialect=dialect;BuildPlan();}Refresh();
    }
    private void Import(){var dialog=new OpenFileDialog{Filter="Images / GIF|*.png;*.jpg;*.jpeg;*.bmp;*.gif"};if(dialog.ShowDialog(System.Windows.Application.Current.MainWindow)==true)ImportFile(dialog.FileName);}
    public void LoadFixture(string file)=>ImportFile(file);
    public void ImportFile(string file)
    {
        preparing?.Cancel();preparing?.Dispose();preparing=new();
        ++planRevision;prepared=null;previews=[];frameOrder=[];frames=[];Plan=null;StaticPlan=null;ModernPlan=null;error=null;uploadResult=null;
        IsPreparing=true;animation.Stop();var ct=preparing.Token;
        Preparation=ImportAsync(file,ct);Refresh();
    }
    private async Task ImportAsync(string file,CancellationToken ct)
    {
        try
        {
            var cached=await Task.Run(()=>{
                if(new FileInfo(file).Length>20*1024*1024)throw new ArgumentException("Asset exceeds 20 MiB.");
                var bytes=File.ReadAllBytes(file);ct.ThrowIfCancellationRequested();
                var directory=Path.Combine(settings.Root,"DisplayAssets");Directory.CreateDirectory(directory);
                var target=Path.Combine(directory,Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(bytes))+Path.GetExtension(file).ToLowerInvariant());
                if(!File.Exists(target))File.WriteAllBytes(target,bytes);return target;
            },ct);
            ct.ThrowIfCancellationRequested();path=cached;selectedProject=null;ProjectName=Path.GetFileNameWithoutExtension(file);sourceName=Path.GetFileName(file);
            await PrepareAsync(null,ct);ct.ThrowIfCancellationRequested();if(prepared is not null)SaveSource();
        }
        catch(OperationCanceledException)when(ct.IsCancellationRequested){}
        catch(Exception ex)when(ex is IOException or UnauthorizedAccessException or ArgumentException){if(!ct.IsCancellationRequested){error="DisplayImportError";CrashEvidence.Record(ex,"Display import");}}
        finally{if(!ct.IsCancellationRequested){IsPreparing=false;Refresh();}}
    }
    private void SaveSource()
    {
        if(Target is not {} key || path is null || prepared is null)return;
        try{preferences.Update(s=>s with{DisplaySources=s.DisplaySources.SetItem(key,new(path,sourceName??prepared.Name,fit.Value.ToString(),StaticPlan?.Sha256))});}
        catch(Exception ex)when(ex is IOException or UnauthorizedAccessException){error="SettingsSaveError";Refresh();}
    }
    private void RestoreSource()
    {
        var saved=Target is {} key?preferences.Settings.DisplaySources.GetValueOrDefault(key):null;
        path=saved?.CachedPath;sourceName=saved?.Name;fit=FitModes.Single(x=>x.Value.ToString()==(saved?.Fit??"Fit"));Rebuild();
    }

    private void Rebuild()=>StartPreparation(null);
    private void StartPreparation(DisplayProject? project)
    {
        preparing?.Cancel();preparing?.Dispose();preparing=new();
        ++planRevision;animation.Stop();prepared=null;previews=[];frameOrder=[];frames=[];Plan=null;StaticPlan=null;ModernPlan=null;error=null;uploadResult=null;IsPreparing=true;
        Preparation=PrepareAsync(project,preparing.Token);Refresh();
    }
    private async Task PrepareAsync(DisplayProject? project,CancellationToken ct)
    {
        var file=path;var mode=fit.Value;var bg=background;int capacity=Windows32DisplayGeometry.Capacity(asset.Value);
        try
        {
            if(project is not null)file=await Task.Run(()=>projects.MaterializeAsset(project.AssetId),ct);
            if(file is null)return;
            var image=await cache.LoadAsync(file,capacity,mode,bg,ct);
            ct.ThrowIfCancellationRequested();
            frameOrder=project is not null && project.FrameOrder.Length==image.Frames.Count?project.FrameOrder.ToArray():Enumerable.Range(0,image.Frames.Count).ToArray();
            frames=Enumerable.Range(0,image.Frames.Count).ToArray();selectedFrame=0;
            var nextPreviews=await Task.Run(()=>image.Frames.Select(DisplayImagePreparation.PreviewFrame).ToArray(),ct);
            ct.ThrowIfCancellationRequested();path=file;prepared=image;previews=nextPreviews;
            if(project is null)interval=Math.Clamp(image.Timing.IntervalMs,33,1000);
            await BuildPlanAsync();ct.ThrowIfCancellationRequested();animation.Interval=TimeSpan.FromMilliseconds(interval);if(previews.Length>1)animation.Start();
        }
        catch(OperationCanceledException)when(ct.IsCancellationRequested){}
        catch(Exception ex)when(ex is IOException or ArgumentException or FormatException or NotSupportedException or InvalidOperationException or System.Runtime.InteropServices.COMException)
        {if(!ct.IsCancellationRequested){error="DisplayImportError";CrashEvidence.Record(ex,"Display conversion");}}
        finally{if(!ct.IsCancellationRequested){IsPreparing=false;Refresh();}}
    }
    private int planRevision;
    public Task PlanPreparation {get;private set;}=Task.CompletedTask;
    private void BuildPlan()=>PlanPreparation=BuildPlanAsync();
    private async Task BuildPlanAsync()
    {
        int revision=++planRevision;Plan=null;StaticPlan=null;ModernPlan=null;
        if(prepared is null||profiles.Selected is not {} p)return;
        var pixels=frameOrder.Select(i=>prepared.Frames[i]).ToArray();var profile=p.Profile.HardwareProfileId;var state=asset.Value;var time=interval;
        bool legacyStatic=!Modern&&profile==HardwareProfileId.Codex&&state==DisplayState.Default&&!prepared.IsGif&&prepared.SourceFrames==1;
        try
        {
            var result=await Task.Run(()=> (Modern:Windows32DisplayUploadPlan.Create(profile,state,pixels,time),Legacy:legacyStatic?StaticDisplayPlan.Create(StaticDisplayPlan.ExpectedBinding,pixels):null));
            if(revision!=planRevision)return;ModernPlan=result.Modern;Plan=result.Modern.Transfer;StaticPlan=result.Legacy;Refresh();
        }
        catch(Exception ex)when(ex is ArgumentException or InvalidOperationException){if(revision==planRevision){error="DisplayImportError";Refresh();}}
    }
    private void MoveFrame(int direction)
    {
        int next=selectedFrame+direction;if(next<0||next>=frameOrder.Length)return;
        (frameOrder[selectedFrame],frameOrder[next])=(frameOrder[next],frameOrder[selectedFrame]);selectedFrame=next;BuildPlan();Refresh();
    }
    private async Task SaveProjectAsync()
    {
        if(path is null||prepared is null||profiles.Selected is not {} p)return;
        var file=path;var image=prepared;var order=frameOrder.ToImmutableArray();var name=string.IsNullOrWhiteSpace(ProjectName)?Source:ProjectName;
        var id=selectedProject?.Id??Guid.NewGuid();var profile=p.Profile.HardwareProfileId;var state=asset.Value;var fitName=fit.Value.ToString();var bg=background;var time=interval;
        try
        {
            var assetId=await Task.Run(()=>projects.AddAsset(file));
            var item=new DisplayProject(id,name,profile,state,assetId,fitName,bg,time,order,order.Length,image.VariableTimingConverted){ModifiedAt=DateTimeOffset.UtcNow};
            await Task.Run(()=>projects.Update(project=>project with{DisplayProjects=project.DisplayProjects.Where(x=>x.Id!=item.Id).Append(item).ToImmutableArray()}));
            selectedProject=item;ReloadLibrary();
        }
        catch(Exception ex)when(ex is IOException or UnauthorizedAccessException or ArgumentException){error="ProjectSaveFailed";CrashEvidence.Record(ex,"Save Display project");}Refresh();
    }
    private async Task EditProjectAsync(bool duplicate)
    {
        if(selectedProject is not {} current)return;
        var name=string.IsNullOrWhiteSpace(ProjectName)?current.Name:ProjectName;
        var item=current with{Id=duplicate?Guid.NewGuid():current.Id,Name=duplicate?name+" (copy)":name,ModifiedAt=DateTimeOffset.UtcNow};
        try{await Task.Run(()=>projects.Update(p=>p with{DisplayProjects=p.DisplayProjects.Where(x=>x.Id!=item.Id).Append(item).ToImmutableArray()}));ReloadLibrary();SelectedProject=item;}
        catch(Exception ex)when(ex is IOException or UnauthorizedAccessException or ArgumentException){error="ProjectSaveFailed";}Refresh();
    }
    private void Export()
    {
        if(Plan is null)return;var dialog=new SaveFileDialog{Filter="JSON|*.json",FileName="display-write-plan.json"};if(dialog.ShowDialog()!=true)return;
        try{if(StaticPlan is {} exact){File.WriteAllText(dialog.FileName,JsonSerializer.Serialize(new{Profile=2,State="Default",Slot=9,FrameCount=1,IntervalMs=100,Bytes=25600,exact.Sha256,exact.StartAddress,exact.PixelEnd,exact.EraseEnd,PhysicalUploadAvailable=CanUpload,RequiresOverwriteConfirmation=true,RollbackAvailable=false,Details=PlanText},new JsonSerializerOptions{WriteIndented=true}));return;}File.WriteAllText(dialog.FileName,JsonSerializer.Serialize(new{Plan.Profile,Plan.Asset,Plan.StartSlot,Plan.FrameCount,Plan.IntervalMs,Plan.TotalBytes,PhysicalUploadAllowed=CanUpload,GateReason=CanUpload?null:Availability,Plan.RollbackAvailable,Source=prepared!.Name,Blocks=Plan.Blocks.Select(b=>new{b.Slot,b.Address,b.Sector,b.Length,Prepare=Convert.ToHexString(b.Prepare.AsSpan()),UsbReports=b.UsbA2Reports().Count(),ExpectedResult="AA BB 81 00 CC DD"}),Binding=Convert.ToHexString(Plan.Binding.AsSpan()),Persistence=Convert.ToHexString(Plan.Persistence.AsSpan())},new JsonSerializerOptions{WriteIndented=true}));}
        catch(Exception ex)when(ex is IOException or UnauthorizedAccessException){error="SettingsSaveError";Refresh();}
    }
    private async Task UploadAsync()
    {
        if(Modern){await UploadModernAsync();return;}
        if(StaticPlan is not {} plan)return;
        if(!CanUpload){uploadResult=manager.RealDevice?.ActiveTransport!=AhaKey.Device.PhysicalTransportKind.Usb?"ProductRequiresUsb":!physical.StaticDisplayAvailable?"ProductConnectAccepted":"ProductActivateCodex";Refresh();ConnectionRequested?.Invoke();return;}
        if(!dialogs.ConfirmDisplay(plan,L))return;
        var device=PhysicalControlRuntime.DeviceHash(manager.RealDevice)!;var firmware=manager.RealDevice!.Identity.Firmware;
        uploadResult="DisplayWriting";Refresh();
        try{history.Forget(device,"Display:2:Default");await physical.UploadStaticAsync(plan,"User approved the exact static frame/hash and Profile 2 Default slot 9 overwrite dialog");uploadResult="DisplayWriteAcceptedInspect";
            try{var assetId=path is null?"unknown":projects.AddAsset(path);
            projects.Update(p=>p with{DisplayAllocations=p.DisplayAllocations.Where(x=>x.Profile!=HardwareProfileId.Codex||x.State!=DisplayState.Default).Append(new DisplayAllocationManifest(FirmwareDialect.LegacyWindows,HardwareProfileId.Codex,DisplayState.Default,9,1,plan.StartAddress,plan.EraseEnd+1,plan.Sha256,assetId,"9/1/100",DateTimeOffset.UtcNow,AssetValidationState.SentMetadataConfirmed)).ToImmutableArray()});
            history.Record(new(device,firmware,"Display:2:Default",plan.Sha256,DateTimeOffset.UtcNow));}catch(Exception ex)when(ex is IOException or UnauthorizedAccessException or JsonException){uploadResult="ProductReceiptFailed";}}
        catch(Exception ex)when(ex is not OutOfMemoryException){uploadResult="PhysicalIndeterminate";}
        finally{Refresh();}
    }

    private async Task UploadModernAsync()
    {
        if(!CanUpload||ModernPlan is not {} plan)return;
        var target=plan.Allocation;
        var selectedAsset=selectedProject?.AssetId;var sourcePath=path;
        if(MessageBox.Show($"{ProfileName} / {L[asset.Value.ToString()]}\n{plan.Transfer.FrameCount} / {target.Capacity} frames · {plan.Transfer.IntervalMs} ms · RGB565 160×80\nSlots {target.StartSlot}–{target.StartSlot+plan.Transfer.FrameCount-1}\n{L["DisplayOverwriteNotice"]}",L["DisplayUpload"],MessageBoxButton.OKCancel,MessageBoxImage.Warning)!=MessageBoxResult.OK)return;
        uploadResult="DisplayWriting";Refresh();
        try
        {
            await physical.UploadModernAsync(plan,"User approved normal Windows 3.2 target overwrite preview");
            uploadResult="DisplayWriteAcceptedInspect";
            try
            {
            var assetId=selectedAsset??(sourcePath is null?"unknown":await Task.Run(()=>projects.AddAsset(sourcePath)));
            projects.Update(p=>p with{DisplayAllocations=p.DisplayAllocations.Where(x=>x.Profile!=target.Profile||x.State!=target.State).Append(new DisplayAllocationManifest(FirmwareDialect.WindowsContract32,target.Profile,target.State,target.StartSlot,plan.Transfer.FrameCount,target.StartAddress,target.StartAddress+plan.Transfer.FrameCount*Windows32DisplayGeometry.Stride,plan.Sha256,assetId,$"{target.StartSlot}/{plan.Transfer.FrameCount}/{plan.Transfer.IntervalMs}",DateTimeOffset.UtcNow,AssetValidationState.SentMetadataConfirmed)).ToImmutableArray()});
            }
            catch(Exception ex)when(ex is IOException or UnauthorizedAccessException or JsonException){uploadResult="ProductReceiptFailed";CrashEvidence.Record(ex,"Display written; local receipt failed");}
        }
        catch(Exception ex)when(ex is not OutOfMemoryException){uploadResult="PhysicalIndeterminate";CrashEvidence.Record(ex,"Display upload stopped");}
        finally{Refresh();}
    }
    private void Refresh(){if(Application.Current is {} app && !app.Dispatcher.CheckAccess()){app.Dispatcher.BeginInvoke(Refresh);return;}OnPropertyChanged(string.Empty);ImportCommand.NotifyCanExecuteChanged();ExportCommand.NotifyCanExecuteChanged();ConvertCommand.NotifyCanExecuteChanged();UploadCommand.NotifyCanExecuteChanged();SaveProjectCommand.NotifyCanExecuteChanged();DuplicateProjectCommand.NotifyCanExecuteChanged();RenameProjectCommand.NotifyCanExecuteChanged();OpenProjectCommand.NotifyCanExecuteChanged();}
}

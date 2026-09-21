using System.IO;
using AhaKey.Device;
using AhaKey.Firmware;
using AhaKey.Services;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
namespace AhaKey.Studio.ViewModels;

public sealed class FirmwareViewModel:ObservableObject
{
    private readonly DeviceManager manager;private readonly Services.FirmwareRuntime runtime;
    private FirmwareUpdateCoordinator coordinator=>runtime.Coordinator;
    private CancellationTokenSource? cancellation;
    private bool packageVerified;
    private string? result;
    private string? details;
    public LocalizationService L {get;}
    public string Current=>$"{L["FirmwareInstalled"]}: AhaKey X1  /  {manager.RealDevice?.FirmwareIdentity.ReportedVersion??L["BleUnknown"]}  /  {L["FirmwareProtocol"]} {manager.RealDevice?.FirmwareIdentity.ReportedProtocol??L["BleUnknown"]}";
    private static bool HasPackage=>File.Exists(KnownPackage().ImagePath) && File.Exists(KnownPackage().ProvenancePath);
    public string Package=>HasPackage?L["FirmwareAvailable"]+": 1.4.8  /  CH582M  /  Windows 3.2":L["FirmwarePackageNotBundled"];
    public string? Result=>result is null?null:L[result];
    public string? Details=>details;
    public string Availability=>L[runtime.ComponentStatus];
    public string State=>L["FirmwareState"+ (coordinator.Journal?.State.ToString()??"Idle")];
    public bool CanReinstall=>packageVerified && runtime.ComponentsReady && !runtime.Busy && manager.Operations.Current is null && manager.RealDevice is {ActiveTransport:PhysicalTransportKind.Usb,Observation.IsLive:true,FirmwareIdentity.ReportedModel:1};
    public bool IsCurrent=>manager.RealDevice?.FirmwareIdentity.ReportedVersion=="1.4.8";
    public bool HasNewerPackage=>packageVerified && System.Version.TryParse(manager.RealDevice?.FirmwareIdentity.ReportedVersion,out var current) && current<new System.Version(1,4,8);
    public bool CanCancel=>runtime.Busy && !coordinator.Critical;
    public bool NeedsRecovery=>coordinator.Journal?.State==FirmwareUpdateState.RecoveryRequired;
    public bool CanRetry=>packageVerified && runtime.ComponentsReady && runtime.CanRecover && !runtime.Busy && manager.Operations.Current is null;
    public bool NeedsSetup=>!runtime.ComponentsReady;
    public bool ShowBootInstructions=>runtime.Busy && coordinator.Journal?.State is FirmwareUpdateState.EnteringBootloader or FirmwareUpdateState.WaitingForApplication;
    public string BootInstructions=>L[coordinator.Journal?.State==FirmwareUpdateState.WaitingForApplication?"FirmwareReconnectInstructions":"FirmwareBootInstructions"];
    public AsyncRelayCommand RetryCommand {get;}
    public AsyncRelayCommand ReinstallCommand {get;}
    public AsyncRelayCommand SetupCommand {get;}
    public RelayCommand CancelCommand {get;}
    public RelayCommand RecoveryCommand {get;}

    public AsyncRelayCommand VerifyCommand {get;}
    public AsyncRelayCommand ChooseCommand {get;}
    public FirmwareViewModel(DeviceManager manager,LocalizationService l,Services.FirmwareRuntime runtime)
    {
        this.manager=manager;this.runtime=runtime;L=l;VerifyCommand=new(VerifyAsync,()=>!runtime.Busy);ChooseCommand=new(ChooseAsync,()=>!runtime.Busy);
        ReinstallCommand=new(ReinstallAsync,()=>CanReinstall);CancelCommand=new(()=>cancellation?.Cancel(),()=>CanCancel);
        RetryCommand=new(()=>ReinstallAsync(true),()=>CanRetry);
        SetupCommand=new(async()=>{try{await runtime.InstallDriverAsync();}catch(Exception ex)when(ex is not OutOfMemoryException){result="FirmwareSetupFailed";Refresh();}},()=>!runtime.Busy);
        RecoveryCommand=new(()=>System.Windows.MessageBox.Show(System.Windows.Application.Current.MainWindow,L["FirmwareRecoveryInstructions"],L["Firmware"]));
        runtime.Changed+=Refresh;
        manager.Changed+=Refresh;l.PropertyChanged+=(_,_)=>Refresh();
    }
    public static FirmwarePackage KnownPackage()=>new("AhaKey-X1","CH582","1.4.8","3.2",Path.Combine(AppContext.BaseDirectory,"FirmwarePackages","AhaKey-X1-firmware-1.4.8-ch582.hex"),
        "2A09C21EEBE764390DD2CBC55C5BF7411C2A641DB6F120125D21B66D9C93DD0C","f1903791f2119d02f71eb92afe9efbb360edb06a",Path.Combine(AppContext.BaseDirectory,"FirmwarePackages","AhaKey-X1-firmware-1.4.8-ch582.provenance.json"),"AhaKey X1 / CH582M / physical PY25Q64HA; partition migration not attested");
    private async Task VerifyAsync()
    {
        if(!HasPackage){packageVerified=false;result="FirmwarePackageNotBundled";Refresh();return;}
        try{await runtime.InspectAsync();var validation=await Task.Run(()=>coordinator.VerifyAsync(KnownPackage()));packageVerified=true;result="FirmwarePackageVerified";details=$"SHA-256 {validation.Sha256}  /  {validation.DataBytes:N0} bytes";}
        catch(Exception ex)when(ex is IOException or FormatException or ArgumentException or System.Text.Json.JsonException){packageVerified=false;result="FirmwarePackageInvalid";Services.CrashEvidence.Record(ex,"Verify package");}Refresh();
    }
    private Task ReinstallAsync()=>ReinstallAsync(false);
    private async Task ReinstallAsync(bool recovery)
    {
        if(recovery?!CanRetry:!CanReinstall)return;
        var summary=$"AhaKey X1  /  USB  /  {(recovery?L["FirmwareRecovery"]:manager.RealDevice!.FirmwareIdentity.ReportedVersion)}  ->  1.4.8\n\n{L["FirmwareFlashConfirmation"]}\n\n{L["FirmwareBootInstructions"]}";
        if(System.Windows.MessageBox.Show(System.Windows.Application.Current.MainWindow,summary,L["FirmwareReinstall"],System.Windows.MessageBoxButton.OKCancel,System.Windows.MessageBoxImage.Warning)!=System.Windows.MessageBoxResult.OK)return;
        cancellation=new();
        try{await runtime.UpdateAsync(KnownPackage(),new Progress<string>(value=>{result=value.StartsWith("Firmware",StringComparison.Ordinal)?value:"FirmwareRunning";Refresh();}),cancellation.Token,recovery);result="FirmwareCompleted";}
        catch(Exception ex)when(ex is not OutOfMemoryException){result=coordinator.Journal?.State==FirmwareUpdateState.RecoveryRequired?"FirmwareRecoveryRequired":"FirmwareStopped";Services.CrashEvidence.Record(ex,"Firmware update");}
        finally{cancellation.Dispose();cancellation=null;Refresh();}
    }
    private async Task ChooseAsync()
    {
        var dialog=new OpenFileDialog{Filter="Intel HEX|*.hex"};if(dialog.ShowDialog()!=true)return;
        try{var validation=await Task.Run(()=>{if(new FileInfo(dialog.FileName).Length>2*1024*1024)throw new FormatException();var bytes=File.ReadAllBytes(dialog.FileName);var parsed=FirmwarePackageValidator.ValidateHex(System.Text.Encoding.ASCII.GetString(bytes));return parsed with{Sha256=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(bytes))};});result="FirmwareHexValidUntrusted";details=$"SHA-256 {validation.Sha256} / {validation.DataBytes:N0} bytes";}
        catch(Exception ex)when(ex is IOException or FormatException or UnauthorizedAccessException){result="FirmwarePackageInvalid";}Refresh();
    }
    private void Refresh(){if(System.Windows.Application.Current is {} app&&!app.Dispatcher.CheckAccess()){app.Dispatcher.BeginInvoke(Refresh);return;}OnPropertyChanged(string.Empty);ReinstallCommand.NotifyCanExecuteChanged();RetryCommand.NotifyCanExecuteChanged();VerifyCommand.NotifyCanExecuteChanged();ChooseCommand.NotifyCanExecuteChanged();SetupCommand.NotifyCanExecuteChanged();CancelCommand.NotifyCanExecuteChanged();}
}

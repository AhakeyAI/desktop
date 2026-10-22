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
    private readonly DeviceManager manager;private readonly FirmwareUpdateCoordinator coordinator=new(new PreparedWchIspTransport());
    private string? result;
    public LocalizationService L {get;}
    public string Current=>$"AhaKey X1 · {manager.RealDevice?.FirmwareIdentity.ReportedVersion??L["BleUnknown"]} · {L["FirmwareProtocol"]} {manager.RealDevice?.FirmwareIdentity.ReportedProtocol??L["BleUnknown"]}";
    public bool HasPackage=>File.Exists(KnownPackage().ImagePath)&&File.Exists(KnownPackage().ProvenancePath);
    public string Package=>"1.4.8 · CH582M · Windows 3.2"+(HasPackage?"":" · "+L["FirmwarePackageNotIncluded"]);
    public string? Result=>result;
    public string Availability=>L[coordinator.AvailabilityReason];
    public AsyncRelayCommand VerifyCommand {get;}
    public AsyncRelayCommand ChooseCommand {get;}
    public FirmwareViewModel(DeviceManager manager,LocalizationService l)
    {
        this.manager=manager;L=l;VerifyCommand=new(VerifyAsync,()=>HasPackage);ChooseCommand=new(ChooseAsync);
        manager.Changed+=Refresh;l.PropertyChanged+=(_,_)=>Refresh();
    }
    public static FirmwarePackage KnownPackage()=>new("AhaKey-X1","CH582","1.4.8","3.2",Path.Combine(AppContext.BaseDirectory,"FirmwarePackages","AhaKey-X1-firmware-1.4.8-ch582.hex"),
        "2A09C21EEBE764390DD2CBC55C5BF7411C2A641DB6F120125D21B66D9C93DD0C","f1903791f2119d02f71eb92afe9efbb360edb06a",Path.Combine(AppContext.BaseDirectory,"FirmwarePackages","AhaKey-X1-firmware-1.4.8-ch582.provenance.json"),"AhaKey X1 / CH582M / physical PY25Q64HA; partition migration not attested");
    private async Task VerifyAsync()
    {
        try{var validation=await Task.Run(()=>coordinator.VerifyAsync(KnownPackage()));result=$"{L["FirmwarePackageVerified"]} · SHA-256 {validation.Sha256} · {validation.DataBytes:N0} bytes";}
        catch(Exception ex)when(ex is IOException or FormatException or ArgumentException or System.Text.Json.JsonException){result=L["FirmwarePackageInvalid"];Services.CrashEvidence.Record(ex,"Verify package");}Refresh();
    }
    private async Task ChooseAsync()
    {
        var dialog=new OpenFileDialog{Filter="Intel HEX|*.hex"};if(dialog.ShowDialog()!=true)return;
        try{var validation=await Task.Run(()=>{if(new FileInfo(dialog.FileName).Length>2*1024*1024)throw new FormatException();return FirmwarePackageValidator.ValidateHex(File.ReadAllText(dialog.FileName));});result=$"{L["FirmwareHexValidUntrusted"]} · {validation.DataBytes:N0} bytes";}
        catch(Exception ex)when(ex is IOException or FormatException or UnauthorizedAccessException){result=L["FirmwarePackageInvalid"];}Refresh();
    }
    private void Refresh(){if(System.Windows.Application.Current is {} app&&!app.Dispatcher.CheckAccess()){app.Dispatcher.BeginInvoke(Refresh);return;}OnPropertyChanged(string.Empty);}
}

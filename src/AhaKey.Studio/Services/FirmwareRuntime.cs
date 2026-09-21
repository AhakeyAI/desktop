using System.IO;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Firmware;
using AhaKey.Services;
using Windows.Devices.Enumeration;
namespace AhaKey.Studio.Services;

public sealed class FirmwareRuntime
{
    private readonly DeviceManager manager;
    private readonly RealDeviceRuntime connections;
    private readonly IntegrationRuntime integrations;
    private readonly SettingsStore settings;
    private string? applicationHash;
    private sealed record RecoveryTarget(string ApplicationHash,string PackageHash);
    private string RecoveryPath=>Path.Combine(settings.Root,"Firmware","target.json");
    public bool CanRecover=>Coordinator.Journal?.State==FirmwareUpdateState.RecoveryRequired && File.Exists(RecoveryPath);
    private bool wasServing;
    public bool Busy {get;private set;}
    public FirmwareUpdateCoordinator Coordinator {get;private set;}
    public event Action? Changed;
    public string ComponentStatus {get;private set;}="FirmwareCheckingComponents";
    public bool ComponentsReady {get;private set;}
    public string Root {get;}=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System).Substring(0,3),"WCH.CN","App","WCHISPTool");
    public FirmwareRuntime(DeviceManager manager,RealDeviceRuntime connections,IntegrationRuntime integrations,SettingsStore settings)
    {
        this.manager=manager;this.connections=connections;this.integrations=integrations;this.settings=settings;
        Coordinator=new(new PreparedWchIspTransport(),Path.Combine(settings.Root,"Firmware","update.json"));
    }
    public async Task InspectAsync()
    {
        var runtime=await Task.Run(()=>WchRuntime.Detect(Root));
        using var service=Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\CH375_A64");
        ComponentsReady=runtime is not null && service is not null;
        ComponentStatus=runtime is null?"FirmwareComponentMissing":service is null?"FirmwareDriverMissing":"FirmwareComponentsReady";
        if(runtime is not null && !Busy)
        {
            Coordinator=new(new WchFlashTransport(runtime,new WchProcessRunner(),Path.Combine(settings.Root,"Firmware","operations"),WaitForBootloaderAsync,WaitForApplicationAsync),Path.Combine(settings.Root,"Firmware","update.json"));
            Coordinator.Changed+=()=>Changed?.Invoke();
        }
        Changed?.Invoke();
    }
    public void OpenOfficialSetup()=>Process.Start(new ProcessStartInfo(WchRuntime.OfficialPackageUrl){UseShellExecute=true});
    public async Task InstallDriverAsync()
    {
        var inf=Path.Combine(Root,"WIN 1X","CH375WDM.INF");
        if(!File.Exists(inf)){OpenOfficialSetup();return;}
        // Windows validates the vendor catalog; elevation is limited to this explicit driver action.
        var start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"pnputil.exe"))
        {UseShellExecute=true,Verb="runas",WindowStyle=ProcessWindowStyle.Hidden,Arguments="/add-driver \""+inf+"\" /install"};
        using var process=Process.Start(start)??throw new IOException("Driver setup did not start.");await process.WaitForExitAsync();
        if(process.ExitCode is not (0 or 3010))throw new IOException("Driver setup failed.");await InspectAsync();
    }
    public async Task UpdateAsync(FirmwarePackage package,IProgress<string> progress,CancellationToken ct,bool recovery=false)
    {
        if(Busy || !ComponentsReady || manager.RealDevice is not {} device)
            throw new InvalidOperationException("Known connected USB device and update components required.");
        await FirmwarePackageValidator.ValidateAsync(package,ct);
        if(recovery)
        {
            if(!CanRecover)throw new InvalidOperationException("No interrupted update target.");
            var target=JsonSerializer.Deserialize<RecoveryTarget>(await File.ReadAllTextAsync(RecoveryPath,ct));
            if(target is null || target.PackageHash!=package.Sha256 || Coordinator.Journal?.Sha256!=package.Sha256)throw new InvalidOperationException("Recovery package does not match the interrupted update.");
            applicationHash=target.ApplicationHash;
        }
        else
        {
            if(device.ActiveTransport!=manager.Operations.SelectTransport(OperationRequirement.FirmwareFlash,null,false) || device.Observation is not {IsLive:true} || device.FirmwareIdentity is not {ReportedModel:1,Dialect:FirmwareDialect.WindowsContract32})throw new InvalidOperationException("Known connected USB device required.");
            var path=device.Usb?.Diagnostics.Selected?.Path??throw new InvalidOperationException("USB identity unavailable.");
            applicationHash=Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(path.ToUpperInvariant())));
            Directory.CreateDirectory(Path.GetDirectoryName(RecoveryPath)!);
            using var targetFile=new FileStream(RecoveryPath,FileMode.Create,FileAccess.Write,FileShare.None);
            JsonSerializer.Serialize(targetFile,new RecoveryTarget(applicationHash,package.Sha256));targetFile.Flush(true);
        }
        // Stop event production and recovery before taking exclusive firmware ownership.
        if(connections.Busy || !await manager.Operations.WaitAsync(0,ct))throw new InvalidOperationException("Device busy.");
        Busy=true;Changed?.Invoke();wasServing=integrations.Manager.Server.Running;
        try
        {
            try
            {
                manager.Operations.Describe("Firmware flash",null,PhysicalTransportKind.Usb,true);
                connections.SuspendRecovery();
                await integrations.Manager.Server.DisposeAsync();
                await device.DisconnectAsync(ct);
                if(device.ActiveTransport!=PhysicalTransportKind.Usb)await device.SelectTransportAsync(PhysicalTransportKind.Usb);
                await Coordinator.UpdateAsync(package,true,progress,ct);
                manager.Operations.Confirm("Firmware and capability identity verified");
            }
            catch{manager.Operations.Fail(Coordinator.Journal?.State==FirmwareUpdateState.RecoveryRequired);throw;}
            finally{manager.Operations.Release();}
        }
        finally
        {
            Busy=false;Changed?.Invoke();
            // A failed update stays paused; no feedback writes into an uncertain recovered device.
            if(wasServing && Coordinator.Journal?.State==FirmwareUpdateState.Completed)integrations.Manager.Server.Start();
        }
    }
    private static async Task WaitForBootloaderAsync(CancellationToken ct)
    {
        var until=DateTimeOffset.UtcNow+TimeSpan.FromMinutes(2);
        while(DateTimeOffset.UtcNow<until)
        {
            ct.ThrowIfCancellationRequested();
            var devices=await DeviceInformation.FindAllAsync("System.Devices.Present:=System.StructuredQueryType.Boolean#True",null,DeviceInformationKind.Device).AsTask(ct);
            var matches=devices.Where(d=>d.Id.Contains("VID_4348&PID_55E0",StringComparison.OrdinalIgnoreCase)).ToArray();
            if(matches.Length>1)throw new InvalidOperationException("Multiple ISP devices; unplug other programmers.");
            if(matches.Length==1)return;
            await Task.Delay(750,ct);
        }
        throw new TimeoutException("ISP not detected; no programming started.");
    }
    private async Task<FirmwareIdentity> WaitForApplicationAsync(CancellationToken ct)
    {
        var device=manager.RealDevice!;
        var until=DateTimeOffset.UtcNow+TimeSpan.FromSeconds(90);
        while(DateTimeOffset.UtcNow<until)
        {
            var found=await device.Usb!.DiscoverAsync(ct);
            if(found.Candidate is {} candidate)
            {
                if(Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(candidate.Path.ToUpperInvariant())))!=applicationHash)throw new InvalidOperationException("Returning application identity changed; recovery verification required.");
                await device.ConnectAsync(ct); // normal handshake: 00 followed by 9F
                return device.FirmwareIdentity;
            }
            await Task.Delay(750,ct);
        }
        throw new TimeoutException("Application did not return; use firmware recovery.");
    }
}

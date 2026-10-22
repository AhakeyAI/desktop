using System.Text.Json;
using AhaKey.Core;
namespace AhaKey.Firmware;
public enum FirmwareUpdateState { Idle, Preflight, WaitingForDevice, EnteringBootloader, BootloaderDetected, Erasing, Programming, Verifying, Rebooting, WaitingForApplication, ValidatingFirmware, Completed, Failed, RecoveryRequired }
public sealed record FirmwareUpdateJournal(Guid Id,string Version,string Sha256,FirmwareUpdateState State,DateTimeOffset UpdatedAt,string? Detail=null);
public sealed class FirmwareUpdateCoordinator
{
    private readonly IFlashTransport transport;
    private readonly SemaphoreSlim gate=new(1,1);
    private readonly string? journalPath;
    public FirmwareUpdateJournal? Journal {get;private set;}
    public bool Critical {get;private set;}
    public event Action? Changed;
    public string AvailabilityReason=>transport.AvailabilityReason;
    public FirmwareUpdateCoordinator(IFlashTransport transport,string? journalPath=null)
    {
        this.transport=transport;this.journalPath=journalPath;
        if(journalPath is not null && File.Exists(journalPath))
        {
            try { Journal=JsonSerializer.Deserialize<FirmwareUpdateJournal>(File.ReadAllText(journalPath)); }
            catch(Exception ex)when(ex is IOException or JsonException){Journal=new(Guid.NewGuid(),"unknown","",FirmwareUpdateState.RecoveryRequired,DateTimeOffset.UtcNow,"JournalUnreadable");}
            if(Journal is {} j && j.State is not (FirmwareUpdateState.Completed or FirmwareUpdateState.Failed or FirmwareUpdateState.Idle))
                Journal=j with{State=FirmwareUpdateState.RecoveryRequired,Detail="Interrupted update; inspect device before retry"};
        }
    }
    public Task<PackageValidation> VerifyAsync(FirmwarePackage p,CancellationToken ct=default)=>FirmwarePackageValidator.ValidateAsync(p,ct);
    private void State(FirmwareUpdateState state,string? detail=null)
    {
        Journal=Journal! with{State=state,UpdatedAt=DateTimeOffset.UtcNow,Detail=detail};
        if(journalPath is not null)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(journalPath)!);
            var temp=journalPath+".tmp";
            using(var file=new FileStream(temp,FileMode.Create,FileAccess.Write,FileShare.None)){JsonSerializer.Serialize(file,Journal);file.Flush(true);}
            File.Move(temp,journalPath,true);
        }
        Changed?.Invoke();
    }
    public async Task<FirmwareIdentity> UpdateAsync(FirmwarePackage package,bool explicitFlashAuthorization,IProgress<string> progress,CancellationToken ct=default)
    {
        if(!explicitFlashAuthorization)throw new InvalidOperationException("Explicit firmware authorization is required.");
        if(!string.IsNullOrEmpty(AvailabilityReason))throw new NotSupportedException(AvailabilityReason);
        await gate.WaitAsync(ct);
        bool programming=false;
        try
        {
            Journal=new(Guid.NewGuid(),package.Version,package.Sha256,FirmwareUpdateState.Preflight,DateTimeOffset.UtcNow);
            State(FirmwareUpdateState.Preflight);var validation=await VerifyAsync(package,ct);
            State(FirmwareUpdateState.WaitingForDevice);State(FirmwareUpdateState.EnteringBootloader);
            await transport.EnterUpdateModeAsync(ct);State(FirmwareUpdateState.BootloaderDetected);
            ct.ThrowIfCancellationRequested();Critical=true;programming=true;
            // The vendor command owns erase/program/verify. Do not manufacture intermediate progress.
            State(FirmwareUpdateState.Programming,"Vendor erase/program/verify running");
            await transport.ProgramAndVerifyAsync(package,validation,progress,CancellationToken.None);
            State(FirmwareUpdateState.Verifying,"Vendor verification completed");
            State(FirmwareUpdateState.Rebooting);State(FirmwareUpdateState.WaitingForApplication);
            var identity=await transport.RebootAndReadIdentityAsync(CancellationToken.None);
            State(FirmwareUpdateState.ValidatingFirmware);
            if(identity.IdentitySource!=IdentitySource.PhysicalTelemetry || identity.ReportedVersion!=package.Version || identity.ReportedProtocol!=package.Protocol || identity.ReportedModel!=1 || identity.ReportedCapabilities!=package.ExpectedCapabilities)
                throw new InvalidOperationException("Post-flash identity/capabilities mismatch.");
            State(FirmwareUpdateState.Completed);progress.Report("Firmware identity verified");return identity;
        }
        catch(Exception ex)
        {State(programming?FirmwareUpdateState.RecoveryRequired:FirmwareUpdateState.Failed,ex.GetType().Name);throw;}
        finally{Critical=false;gate.Release();Changed?.Invoke();}
    }
}

using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Services;
namespace AhaKey.Studio.Services;
public sealed class ProfileActivationRuntime(DeviceManager manager,PhysicalControlRuntime controls,ProfileSelectionService preferences)
{
    public bool Busy {get;private set;}
    public string? ErrorKey {get;private set;}
    public bool Available=>!controls.UsbOperationBusy && manager.RealBackendSelected && manager.RealDevice?.Observation.IsLive==true && (controls.Acceptance?.ProfileSwitch?.Accepted==true || manager.RealDevice.FirmwareIdentity is {Dialect:FirmwareDialect.WindowsContract32,ReportedVersion:"1.4.8",ReportedProtocol:"3.2",ReportedModel:1});
    public bool Enabled=>preferences.Settings.ActivateHardwareProfile;
    public event Action? Changed;
    public void Enable(bool value){preferences.Update(s=>s with{ActivateHardwareProfile=value});if(!value)ErrorKey=null;Changed?.Invoke();}
    public async Task ActivateAsync(HardwareProfileId profile)
    {
        if(!Enabled)return;
        if(Busy){ErrorKey="ProductProfileBusy";Changed?.Invoke();return;}
        if(!Available || manager.RealDevice?.Observation is not {IsLive:true,SessionId:{} session}){ErrorKey="ProductProfileUnavailable";Changed?.Invoke();return;}
        if(manager.RealDevice.Observation.Status?.WorkMode==(int)profile){ErrorKey=null;Changed?.Invoke();return;}
        Busy=true;ErrorKey=null;Changed?.Invoke();
        try
        {
            controls.Intent(new{Operation="Activate hardware profile",Session=session,Profile=profile,At=DateTimeOffset.UtcNow,Approval="Persisted user opt-in and explicit profile selection"});
            await manager.ExecuteControlsAsync(ApprovedControlPlan.WorkProfile(session,"User enabled profile activation and selected "+profile,profile),controls.Record);
            var status=await manager.RefreshApprovalStatusAsync(default);
            if(status is not {IsLive:true} || status.SessionId!=session || status.Status?.WorkMode!=(int)profile)throw new InvalidOperationException("Profile not confirmed.");
        }
        catch(Exception ex)when(ex is not OutOfMemoryException){ErrorKey="ProductProfileFailed";}
        finally{Busy=false;Changed?.Invoke();}
    }
}

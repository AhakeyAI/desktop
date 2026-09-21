using AhaKey.Core;
using AhaKey.Protocol;
using System.Collections.Immutable;
using System.IO;
using AhaKey.Device;
using AhaKey.Services;
namespace AhaKey.Studio.Services;

public sealed class LocalProjectRuntime(DeviceManager manager,LocalDeviceProjectStore store,ProfileSelectionService preferences)
{
    private bool applying;
    public LocalDeviceProjectStore Store=>store;
    public string? ErrorKey {get;private set;}
    public void Initialize()
    {
        bool migrate=!File.Exists(store.FilePath);var project=store.LoadOrMigrate(manager.Tracker.Draft,preferences.Settings);
        try{if(!store.ReadOnly)Apply(project,false);ErrorKey=store.ErrorKey;}catch(Exception ex)when(ex is not OutOfMemoryException){ErrorKey="ProjectLoadFailed";}
        if(migrate&&!store.ReadOnly)MigrateDisplaySources();
        manager.Changed+=Capture;preferences.Changed+=Capture;
    }
    private void MigrateDisplaySources()
    {
        foreach(var pair in preferences.Settings.DisplaySources)
        {
            try
            {
                var pieces=pair.Key.Split(':');var profile=(HardwareProfileId)int.Parse(pieces[0]);var state=(DisplayState)int.Parse(pieces[1]);
                var source=pair.Value;if(!File.Exists(source.CachedPath))continue;
                var image=DisplayImagePreparation.Load(source.CachedPath,DisplayLimits.MaximumFrames(state),Enum.Parse<DisplayFitMode>(source.Fit));
                var id=store.AddAsset(source.CachedPath);var item=new DisplayProject(Guid.NewGuid(),source.Name,profile,state,id,source.Fit,"#000000",100,[..Enumerable.Range(0,image.Frames.Count)],image.Frames.Count,image.VariableTimingConverted);
                store.Update(p=>p with{DisplayProjects=p.DisplayProjects.Add(item)});
            }
            catch(Exception ex)when(ex is not OutOfMemoryException){ErrorKey="ProjectMigrationPartial";}
        }
    }
    public void Import(LocalDeviceProject reviewed)
    {
        // Import is local authoring. Existing physical opt-ins are not enabled by a file.
        reviewed=reviewed with{IntegrationPreferences=store.Current!.IntegrationPreferences,Voice=reviewed.Voice with{Enabled=false}};
        applying=true;try{store.Import(reviewed);Apply(reviewed,true);}finally{applying=false;}
    }
    private void Apply(LocalDeviceProject p,bool imported)
    {
        applying=true;
        try
        {
            manager.Edit(p.Desired);
            preferences.Update(s=>s with{KeyLocalNames=p.LocalKeyNames,CustomProfileName=p.ProfileNames.GetValueOrDefault(HardwareProfileId.Custom)??s.CustomProfileName,
                IntegrationAutoStart=p.IntegrationPreferences.ServiceAutoStart,PhysicalFeedback=p.IntegrationPreferences.PhysicalFeedback,
                ActivateHardwareProfile=p.IntegrationPreferences.ActivateProfile,AdvancedLightingMapping=p.IntegrationPreferences.AdvancedLightingMapping});
        }
        finally{applying=false;}
    }
    private void Capture()
    {
        if(applying||store.ReadOnly||store.Current is null)return;
        var current=store.Current;
        if(manager.RealDevice?.Observation is {IsLive:true,StatusAt:{} at,Status:{} status} observation && !current.PhysicalReadObservations.Any(x=>x.Resource=="00"&&x.At==at))
        {
            try{store.Update(p=>p with{PhysicalReadObservations=p.PhysicalReadObservations.Add(new("00",System.Text.Json.JsonSerializer.Serialize(status),at,observation.Transport.ToString())).TakeLast(64).ToImmutableArray()});current=store.Current!;}
            catch(Exception ex)when(ex is not OutOfMemoryException){ErrorKey="ProjectSaveFailed";}
        }
        var next=LocalDeviceProjectStore.CapturePreferences(current with{Desired=manager.Tracker.Draft},preferences.Settings);
        if(current.Desired.EquivalentTo(next.Desired)&&current.LocalKeyNames.SequenceEqual(next.LocalKeyNames)&&current.ProfileNames.SequenceEqual(next.ProfileNames)&&current.IntegrationPreferences==next.IntegrationPreferences)return;
        try{store.Update(latest=>LocalDeviceProjectStore.CapturePreferences(latest with{Desired=manager.Tracker.Draft},preferences.Settings));ErrorKey=null;}catch(Exception ex)when(ex is not OutOfMemoryException){ErrorKey="ProjectSaveFailed";}
    }
}

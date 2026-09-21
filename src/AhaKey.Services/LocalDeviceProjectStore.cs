using System.Collections.Immutable;
using System.Security.Cryptography;
using System.Text.Json;
using AhaKey.Core;
namespace AhaKey.Services;

public sealed class LocalDeviceProjectStore(SettingsStore settings)
{
    private readonly object sync=new();
    public string FilePath=>Path.Combine(settings.Root,"project.v1.json");
    public LocalDeviceProject? Current {get;private set;}
    public bool ReadOnly {get;private set;}
    public string? ErrorKey {get;private set;}
    public event Action? Changed;
    public LocalDeviceProject LoadOrMigrate(DeviceConfiguration draft,StudioSettings preferences)
    {
        if(File.Exists(FilePath))
        {
            try{Current=Read(FilePath);var recovered=Current.KeyWriteAttempts.ToImmutableDictionary(x=>x.Key,x=>x.Value.State==KeyWriteProvenance.Sending?x.Value with{State=KeyWriteProvenance.OutcomeUncertain}:x.Value);if(recovered.Any(x=>x.Value!=Current.KeyWriteAttempts[x.Key]))Save(Current with{KeyWriteAttempts=recovered});return Current;}
            catch(Exception ex)when(ex is not OutOfMemoryException){ReadOnly=true;ErrorKey="ProjectLoadFailed";}
        }
        Current=CapturePreferences(new(1,Guid.NewGuid(),"AhaKey Studio project",draft),preferences);
        if(!ReadOnly)Save(Current);
        return Current;
    }
    public static LocalDeviceProject CapturePreferences(LocalDeviceProject project,StudioSettings s)=>project with
    {
        LocalKeyNames=s.KeyLocalNames,
        ProfileNames=Profile.Defaults.ToImmutableDictionary(x=>x.HardwareProfileId,x=>x.HardwareProfileId==HardwareProfileId.Custom?s.CustomProfileName??x.DisplayName:x.DisplayName),
        IntegrationPreferences=new(s.IntegrationAutoStart,s.PhysicalFeedback,s.ActivateHardwareProfile,s.AdvancedLightingMapping)
    };
    public void Update(Func<LocalDeviceProject,LocalDeviceProject> update)
    {lock(sync){if(Current is null)throw new InvalidOperationException("Project not loaded.");Save(update(Current));}Changed?.Invoke();}
    private void Save(LocalDeviceProject value)
    {
        if(ReadOnly)throw new IOException("Unreadable project preserved; read-only session.");
        Validate(value,!ReferenceEquals(Current?.EmbeddedAssets,value.EmbeddedAssets));Directory.CreateDirectory(settings.Root);var temp=FilePath+"."+Guid.NewGuid().ToString("N")+".tmp";
        try{using(var file=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None)){JsonSerializer.Serialize(file,value);file.Flush(true);}File.Move(temp,FilePath,true);Current=value;ErrorKey=null;}
        finally{if(File.Exists(temp))File.Delete(temp);}
    }
    public void Export(string path)
    {
        var project=Current??throw new InvalidOperationException();
        // Portable exports carry authoring data, never device paths/IDs, acceptance receipts or physical claims.
        var desired=project.Desired with{Profiles=project.Desired.Profiles.ToImmutableDictionary(x=>x.Key,x=>x.Value with{Display=x.Value.Display.ToImmutableDictionary(d=>d.Key,d=>d.Value with{SourceFile=null})})};
        var portable=project with{Desired=desired,LastSuccessfullySent=ImmutableDictionary<string,LocalSentState>.Empty,KeyWriteAttempts=ImmutableDictionary<string,LocalSentState>.Empty,PhysicalReadObservations=[],BehaviorVerifications=[],DisplayAllocations=[],Voice=project.Voice with{Enabled=false,ApplicationPath=null}};
        File.WriteAllText(path,JsonSerializer.Serialize(portable,new JsonSerializerOptions{WriteIndented=true}));
    }
    public LocalDeviceProject PreviewImport(string path)=>Read(path) with{Id=Guid.NewGuid(),LastSuccessfullySent=ImmutableDictionary<string,LocalSentState>.Empty,KeyWriteAttempts=ImmutableDictionary<string,LocalSentState>.Empty,PhysicalReadObservations=[],BehaviorVerifications=[],DisplayAllocations=[]};
    public void Import(LocalDeviceProject reviewed)
    {
        if(File.Exists(FilePath))File.Copy(FilePath,FilePath+"."+DateTimeOffset.UtcNow.ToString("yyyyMMddHHmmssfff")+".bak",false);
        Update(_=>reviewed);
    }
    public string AddAsset(string path)
    {
        var bytes=File.ReadAllBytes(path);if(bytes.Length>20*1024*1024)throw new ArgumentException("Asset exceeds 20 MiB.");
        var id=Convert.ToHexString(SHA256.HashData(bytes));Update(p=>p with{EmbeddedAssets=p.EmbeddedAssets.SetItem(id,Convert.ToBase64String(bytes))});return id;
    }
    public string MaterializeAsset(string id)
    {
        var bytes=Convert.FromBase64String(Current!.EmbeddedAssets[id]);var directory=Path.Combine(settings.Root,"ProjectAssets");Directory.CreateDirectory(directory);
        var path=Path.Combine(directory,id+".image");if(!File.Exists(path))File.WriteAllBytes(path,bytes);return path;
    }
    private static LocalDeviceProject Read(string path)
    {
        if(new FileInfo(path).Length>100*1024*1024)throw new ArgumentException("Project exceeds 100 MiB.");
        var project=JsonSerializer.Deserialize<LocalDeviceProject>(File.ReadAllText(path))??throw new JsonException();Validate(project);return project;
    }
    public static void Validate(LocalDeviceProject p)=>Validate(p,true);
    private static void Validate(LocalDeviceProject p,bool validateAssets)
    {
        if(p.SchemaVersion!=1||p.Id==Guid.Empty||string.IsNullOrWhiteSpace(p.Name)||p.Name.Length>128)throw new ArgumentException("Invalid project schema.");
        new DeviceCapabilities(true).Validate(p.Desired);
        if(p.ProfileNames is null||p.LocalKeyNames is null||p.EmbeddedAssets is null||p.IntegrationPreferences is null||p.Voice is null||p.LastSuccessfullySent is null||p.KeyWriteAttempts is null||p.DisplayProjects.IsDefault||p.DisplayAllocations.IsDefault)throw new ArgumentException("Missing project data.");
        if(p.LocalKeyNames.Any(x=>!System.Text.RegularExpressions.Regex.IsMatch(x.Key,"^[0-3]:[0-3]$")||(x.Value is null||x.Value.Length>80))||p.ProfileNames.Any(x=>!Enum.IsDefined(x.Key)||string.IsNullOrWhiteSpace(x.Value)||x.Value.Length>48))throw new ArgumentException("Invalid names.");
        if(p.IntegrationPreferences.PhysicalFeedback is null||p.IntegrationPreferences.PhysicalFeedback.Any(x=>!System.Text.RegularExpressions.Regex.IsMatch(x,"^[0-3]:(Codex|Claude|Cursor)$")))throw new ArgumentException("Invalid integration preferences.");
        long total=0;foreach(var pair in validateAssets?p.EmbeddedAssets:System.Collections.Immutable.ImmutableDictionary<string,string>.Empty){var bytes=Convert.FromBase64String(pair.Value);total+=bytes.Length;if(bytes.Length>20*1024*1024||total>64*1024*1024||pair.Key!=Convert.ToHexString(SHA256.HashData(bytes)))throw new ArgumentException("Invalid asset hash/size.");}
        foreach(var d in p.DisplayProjects)if(d is null||string.IsNullOrWhiteSpace(d.Name)||d.Name.Length>128||d.Background is null||!System.Text.RegularExpressions.Regex.IsMatch(d.Background,"^#[0-9a-fA-F]{6}$")||d.FrameOrder.IsDefault||d.Id==Guid.Empty||!Enum.IsDefined(d.Profile)||!Enum.IsDefined(d.State)||d.Fit is not ("Fit" or "Crop")||d.UniformIntervalMs is <33 or >1000||(d.FrameCount<1||d.FrameCount>DisplayLimits.MaximumFrames(d.State))||!p.EmbeddedAssets.ContainsKey(d.AssetId)||d.FrameOrder.Length!=d.FrameCount||d.FrameOrder.Any(x=>x<0||x>=d.FrameCount)||d.FrameOrder.Distinct().Count()!=d.FrameCount)throw new ArgumentException("Invalid display project.");
        if(!Enum.IsDefined(p.Voice.Action)||p.Voice.Shortcut is {} shortcut&&(!ShortcutGesture.TryParse(shortcut,out var gesture)||gesture!.Key=="F18"))throw new ArgumentException("Invalid voice action.");
        if(p.Voice.Shortcut is {} hostShortcut)HostShortcutPlan.Create(hostShortcut);
    }
}

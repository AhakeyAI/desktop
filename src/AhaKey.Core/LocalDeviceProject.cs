using System.Collections.Immutable;
namespace AhaKey.Core;

public enum KeyWriteProvenance { LocalChanges, Sending, SentToDevice, VerifiedByKeyPress, SendFailed, OutcomeUncertain }
public sealed record LocalSentState(string Target,string ValueHash,DateTimeOffset SentAt,KeyWriteProvenance State);
public sealed record PhysicalReadObservation(string Resource,string Value,DateTimeOffset At,string Source);
public sealed record BehaviorVerification(string Target,string ValueHash,DateTimeOffset At);
public sealed record DisplayProject(Guid Id,string Name,HardwareProfileId Profile,DisplayState State,string AssetId,
    string Fit,string Background,int UniformIntervalMs,ImmutableArray<int> FrameOrder,int FrameCount,bool VariableTimingConverted)
{
    public DateTimeOffset? ModifiedAt {get;init;}
    public string LibraryDetail => $"{(FrameCount>1?"GIF":"Image")} · {FrameCount} × {UniformIntervalMs} ms · {FrameCount*UniformIntervalMs} ms";
    public string ModifiedText => ModifiedAt?.ToLocalTime().ToString("g")??"—";
}
public enum AssetValidationState { SentMetadataConfirmed, VisuallyVerified, Interrupted, OutcomeUncertain }
public sealed record DisplayAllocationManifest(FirmwareDialect FirmwareDialect,HardwareProfileId Profile,DisplayState State,
    int SlotStart,int SlotCount,long ByteStart,long ByteEndExclusive,string PixelHash,string SourceAssetId,
    string Binding,DateTimeOffset WrittenAt,AssetValidationState PhysicalValidationState)
{
    public static string UnmanagedOwnership=>"Unknown ownership";
}
public enum VoiceHostAction { None, WindowsVoiceTyping, ActivateApplication, LocalShortcut }
public sealed record VoiceRoutingSettings(bool Enabled=false,VoiceHostAction Action=VoiceHostAction.None,string? ApplicationPath=null,string? Shortcut=null);
public sealed record ProjectIntegrationPreferences(bool ServiceAutoStart,ImmutableHashSet<string> PhysicalFeedback,bool ActivateProfile,bool AdvancedLightingMapping);
public sealed record LocalDeviceProject(int SchemaVersion,Guid Id,string Name,DeviceConfiguration Desired)
{
    public ImmutableDictionary<HardwareProfileId,string> ProfileNames {get;init;}=ImmutableDictionary<HardwareProfileId,string>.Empty;
    public ImmutableDictionary<string,string> LocalKeyNames {get;init;}=ImmutableDictionary<string,string>.Empty;
    public ImmutableDictionary<string,LocalSentState> LastSuccessfullySent {get;init;}=ImmutableDictionary<string,LocalSentState>.Empty;
    public ImmutableDictionary<string,LocalSentState> KeyWriteAttempts {get;init;}=ImmutableDictionary<string,LocalSentState>.Empty;
    public ImmutableArray<PhysicalReadObservation> PhysicalReadObservations {get;init;}=[];
    public ImmutableArray<BehaviorVerification> BehaviorVerifications {get;init;}=[];
    public string UnknownPhysicalState {get;init;}="Unobserved configuration and pixel contents remain unknown";
    public ImmutableArray<DisplayProject> DisplayProjects {get;init;}=[];
    public ImmutableArray<DisplayAllocationManifest> DisplayAllocations {get;init;}=[];
    public ImmutableDictionary<string,string> EmbeddedAssets {get;init;}=ImmutableDictionary<string,string>.Empty;
    public ProjectIntegrationPreferences IntegrationPreferences {get;init;}=new(false,[],false,false);
    public VoiceRoutingSettings Voice {get;init;}=new();
    public bool IsDeviceBackup=>false;
}

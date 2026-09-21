namespace AhaKey.Core;

public enum FirmwareDialect { Unknown, LegacyWindows, WindowsContract32, RuntimeTaskPictureV3 }
public enum IdentitySource { Unknown, PhysicalTelemetry, SourceDerivedFixture, ExplicitRuntimeContract }
public sealed record FirmwareIdentity(byte? ReportedMajor, byte? ReportedMinor, byte? ReportedPatch,
    string? ReportedProtocol, byte? ReportedModel, uint? ReportedCapabilities,
    string ObservedBehaviorFingerprint, string? KnownBuildHash, IdentitySource IdentitySource,
    FirmwareDialect Dialect)
{
    public string? ReportedVersion => ReportedMajor is {} major && ReportedMinor is {} minor
        ? ReportedPatch is {} patch ? $"{major}.{minor}.{patch}" : $"{major}.{minor}" : null;
    public static FirmwareIdentity Unknown { get; } = new(null,null,null,null,null,null,"",null,IdentitySource.Unknown,FirmwareDialect.Unknown);
}
public enum FeatureTransport { Usb, Bluetooth }
public enum DeviceFeature { ShortcutWrite, GenericK1Remap, RuntimeLighting, BrightnessWrite, StaticDisplay, ConfigResourceRead, FullConfigurationReadback }
public sealed record DeviceFeatureSupport(DeviceFeature Feature, bool SourceKnown, bool DeclaredByDevice,
    bool PhysicallyValidated, FeatureTransport Transport, FirmwareDialect FirmwareDialect,
    string ResourceProfileScope, string Limitations, string? UnavailableReason)
{
    public bool Available => SourceKnown && (DeclaredByDevice || PhysicallyValidated) && UnavailableReason is null;
}
// Receipts attest behavior on a privately matched device/route, not on every binary reporting 1.0.
public sealed record FeatureEvidence(bool Keys = false, bool StaticDisplay = false,
    bool Effect01 = false, bool Neutral00 = false);
public sealed class DeviceFeatureCatalog(FirmwareIdentity identity, FeatureTransport transport, FeatureEvidence evidence)
{
    private bool Modern => identity.Dialect==FirmwareDialect.WindowsContract32 && identity.ReportedProtocol=="3.2" && identity.ReportedModel==1 && identity.ReportedVersion=="1.4.8";
    private bool Known => identity.Dialect is FirmwareDialect.LegacyWindows or FirmwareDialect.WindowsContract32;
    private DeviceFeatureSupport Result(DeviceFeature feature,bool declared,bool physical,string scope,string limitation,string? reason) =>
        new(feature,Known,declared,physical&&Known,transport,identity.Dialect,scope,limitation,
            !Known ? "FeatureUnknownDialect" : reason);
    public DeviceFeatureSupport CanWriteShortcut(HardwareProfileId profile,PhysicalKey key) =>
        Result(key==PhysicalKey.K1?DeviceFeature.GenericK1Remap:DeviceFeature.ShortcutWrite,Modern,
            evidence.Keys && Enum.IsDefined(profile) && Enum.IsDefined(key) && key!=PhysicalKey.K1 && transport==FeatureTransport.Usb,
            $"Profile {(int)profile} / {key}","Global save; prior physical value may be unknown",
            key==PhysicalKey.K1?"FeatureManagedVoice":!Enum.IsDefined(profile)||!Enum.IsDefined(key)?"FeatureTargetUnverified":
            !Modern&&transport!=FeatureTransport.Usb?"ProductRequiresUsb":!Modern&&!evidence.Keys?"FeatureTargetUnverified":null);
    public DeviceFeatureSupport CanUploadDisplay(HardwareProfileId profile,DisplayState state,int frameCount,int slot=9)
    {
        if(Modern)
        {
            bool target=Enum.IsDefined(profile)&&Enum.IsDefined(state)&&frameCount>=1&&frameCount<=Windows32DisplayGeometry.Capacity(state);
            bool declared=(identity.ReportedCapabilities.GetValueOrDefault()&0x40)!=0;
            return Result(DeviceFeature.StaticDisplay,declared,false,$"Profile {(int)profile} / {state}","Allocated target overwrite; no pixel rollback; shared save",
                transport!=FeatureTransport.Usb?"ProductRequiresUsb":!declared||!target?"FeatureTargetUnverified":null);
        }
        return Result(DeviceFeature.StaticDisplay,false,identity.Dialect==FirmwareDialect.LegacyWindows && evidence.StaticDisplay && transport==FeatureTransport.Usb &&
            profile==HardwareProfileId.Codex && state==DisplayState.Default && frameCount==1 && slot==9,
            "Profile 2 / Default / slot 9 / one static frame", "Overwrite; no pixel rollback; not atomic",
            identity.Dialect!=FirmwareDialect.LegacyWindows||profile!=HardwareProfileId.Codex||state!=DisplayState.Default||frameCount!=1||slot!=9?"FeatureTargetUnverified":
            transport!=FeatureTransport.Usb?"ProductRequiresUsb":!evidence.StaticDisplay?"FeatureTargetUnverified":null);
    }
    public DeviceFeatureSupport CanUseRuntimeLighting(byte effect) =>
        Result(DeviceFeature.RuntimeLighting,Modern&&effect<=16,effect==0?evidence.Neutral00:effect==1&&evidence.Effect01,
            $"Effect {effect:X2}","Runtime only; no save",
            Modern&&effect<=16||effect==0&&evidence.Neutral00||effect==1&&evidence.Effect01?null:"FeatureEffectUnverified");
    public DeviceFeatureSupport CanSetBrightness() => Result(DeviceFeature.BrightnessWrite,Modern,false,"Global 1..100", "Dirties shared config; 04 persists globally", !Modern?"FeatureBrightnessUnverified":null);
    public DeviceFeatureSupport CanReadConfigResource(byte resource)
    {
        bool declared=Modern&&resource<=2&&(identity.ReportedCapabilities.GetValueOrDefault()&0x400)!=0;
        return Result(DeviceFeature.ConfigResourceRead,declared,false,$"Resource {resource}","Partial live RAM read; no labels/pixels or atomic backup",!declared?"FeatureReadbackUnverified":null) with{SourceKnown=identity.Dialect==FirmwareDialect.WindowsContract32&&resource<=2};
    }
    public DeviceFeatureSupport FullReadback => Result(DeviceFeature.FullConfigurationReadback,false,false,"All", "No full backup command", "FeatureFullReadbackUnavailable") with{SourceKnown=false};
}

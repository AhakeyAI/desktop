using System.Collections.Immutable;
using System.Text;
using AhaKey.Core;
namespace AhaKey.Protocol;

public enum ControlCategory { KeyConfiguration, LightingRuntime, Brightness, ProfileRuntime, LightingConfiguration, ConfigurationRead }
// Closed constructors: no arbitrary frame, macro, map, display or firmware command can enter this path.
public sealed class LegacyControlCommand
{
    public ImmutableArray<byte> Frame { get; }
    public byte Opcode => Frame[2];
    public ControlCategory Category { get; }
    public string Operation { get; }
    private LegacyControlCommand(ControlCategory category, string operation, byte command, params byte[] payload)
    { Category=category; Operation=operation; Frame=[0xAA,0xBB,command,..payload,0xCC,0xDD]; }
    private static void Address(HardwareProfileId profile, PhysicalKey key)
    { if(!Enum.IsDefined(profile) || key is not (PhysicalKey.K2 or PhysicalKey.K3 or PhysicalKey.K4)) throw new ArgumentOutOfRangeException(nameof(key)); }
    public static LegacyControlCommand Shortcut(HardwareProfileId profile, PhysicalKey key, ShortcutGesture gesture)
    {
        Address(profile,key);
        if(!ShortcutGesture.TryParse(gesture.Canonical,out var parsed) || parsed!=gesture) throw new ArgumentException("Invalid shortcut.");
        return new(ControlCategory.KeyConfiguration,"Shortcut",0x73,[0x73,(byte)profile,(byte)key,..gesture.HidSequence]);
    }
    public static LegacyControlCommand Description(HardwareProfileId profile,PhysicalKey key,string label)
    { Address(profile,key); if(!DeviceLabelRules.IsValid(label))throw new ArgumentException("Device label must be printable ASCII, at most 20 bytes.");return new(ControlCategory.KeyConfiguration,"DeviceLabel",0x73,[0x75,(byte)profile,(byte)key,..Encoding.ASCII.GetBytes(label)]); }
    public static LegacyControlCommand SaveKeys() => new(ControlCategory.KeyConfiguration,"GlobalSave",0x04);
    // Dedicated experiment only: fixed profile 2 / key 0, F19 test or F18 restoration.
    // Ordinary Shortcut/Description remain K2-K4 until separate behavioral evidence exists.
    public static LegacyControlCommand K1Experiment(bool restore) =>
        new(ControlCategory.KeyConfiguration,restore?"K1RestoreF18":"K1TestF19",0x73,0x73,2,0,restore?(byte)0x6D:(byte)0x6E);
    public static LegacyControlCommand Effect(byte code)
    {if(code>0x10)throw new ArgumentOutOfRangeException(nameof(code));return new(ControlCategory.LightingRuntime,"RuntimeEffect",0x91,code);}
    public static LegacyControlCommand WorkProfile(HardwareProfileId profile)
    {if(!Enum.IsDefined(profile))throw new ArgumentOutOfRangeException(nameof(profile));return new(ControlCategory.ProfileRuntime,"WorkProfile",0x92,(byte)profile);}
    // Encoding/planning only until transient persistence semantics are accepted separately.
    public static LegacyControlCommand Brightness(byte value)
    {if(value is <1 or >100)throw new ArgumentOutOfRangeException(nameof(value));return new(ControlCategory.Brightness,"Brightness",0x85,value);}
    public static LegacyControlCommand LightingMap(HardwareProfileId profile,IReadOnlyList<byte> values)
    {if(!Enum.IsDefined(profile)||values.Count!=9||values.Any(x=>x>16))throw new ArgumentException("Invalid Windows 3.2 lighting map.");return new(ControlCategory.LightingConfiguration,"LightingMap",0x84,[(byte)profile,..values]);}
    public static LegacyControlCommand AssistantState(byte state)
    {if(state>8)throw new ArgumentOutOfRangeException(nameof(state));return new(ControlCategory.LightingRuntime,"AssistantState",0x90,state);}
    public bool AcceptsResponse(ReadOnlySpan<byte> response) => response.Length==6 && response[0]==0xAA && response[1]==0xBB && response[2]==Opcode && response[3]==0 && response[4]==0xCC && response[5]==0xDD;
    public ImmutableArray<byte> UsbReport()
    {var report=new byte[65];report[1]=0xA1;report[2]=(byte)Frame.Length;Frame.CopyTo(report,3);return [..report];}
}

public sealed record PhysicalKeyValue(ShortcutGesture Shortcut,string Label);
public sealed record KeyWritePlan(HardwareProfileId Profile,PhysicalKey Key,PhysicalKeyValue Value,ImmutableArray<LegacyControlCommand> Commands)
{
    public bool PhysicalReadbackAvailable => false;
    public static KeyWritePlan Create(HardwareProfileId profile,PhysicalKey key,PhysicalKeyValue desired,PhysicalKeyValue? lastAccepted=null)
    {
        var shortcut=LegacyControlCommand.Shortcut(profile,key,desired.Shortcut);
        var label=LegacyControlCommand.Description(profile,key,desired.Label);
        var commands=ImmutableArray.CreateBuilder<LegacyControlCommand>();
        if(lastAccepted?.Shortcut!=desired.Shortcut)commands.Add(shortcut);
        if(lastAccepted?.Label!=desired.Label)commands.Add(label);
        if(commands.Count>0)commands.Add(LegacyControlCommand.SaveKeys());
        return new(profile,key,desired,commands.ToImmutable());
    }
}

public enum PhysicalKeyWriteState { LocalOnly, PendingWrite, WriteAccepted, BehaviorVerified, ReadbackVerified, Indeterminate }
public sealed class PhysicalKeyVerification
{
    public PhysicalKeyWriteState State {get;private set;}=PhysicalKeyWriteState.LocalOnly;
    public PhysicalKeyValue? Accepted {get;private set;}
    public string? Observed {get;private set;}
    public void Begin(){State=PhysicalKeyWriteState.PendingWrite;Accepted=null;Observed=null;}
    public void Accept(PhysicalKeyValue value){if(State!=PhysicalKeyWriteState.PendingWrite)throw new InvalidOperationException();Accepted=value;State=PhysicalKeyWriteState.WriteAccepted;}
    public void Fail(){Accepted=null;State=PhysicalKeyWriteState.Indeterminate;}
    // Invoked only by focused local key capture in an explicitly armed physical test.
    public bool Observe(ShortcutGesture observed)
    {Observed=observed.Display;if(State is not (PhysicalKeyWriteState.WriteAccepted or PhysicalKeyWriteState.BehaviorVerified) || Accepted?.Shortcut!=observed)return false;State=PhysicalKeyWriteState.BehaviorVerified;return true;}
}

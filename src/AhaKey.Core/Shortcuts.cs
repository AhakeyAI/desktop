using System.Collections.Immutable;
namespace AhaKey.Core;
// Values match the source-confirmed Windows host shortcut integer, not a HID report bitmask.
[Flags]
public enum ShortcutModifiers
{
    None=0, LeftShift=0x0100, LeftCtrl=0x0200, LeftAlt=0x0400, LeftWin=0x0800,
    RightShift=0x1000, RightCtrl=0x2000, RightAlt=0x4000, RightWin=0x8000
}
public sealed record ShortcutGesture(ShortcutModifiers Modifiers, string Key)
{
    public static readonly ImmutableArray<(ShortcutModifiers Flag, string Name, byte Hid)> ModifierOrder = [
        (ShortcutModifiers.LeftCtrl,"Ctrl",0xE0), (ShortcutModifiers.RightCtrl,"RightCtrl",0xE4),
        (ShortcutModifiers.LeftShift,"Shift",0xE1), (ShortcutModifiers.RightShift,"RightShift",0xE5),
        (ShortcutModifiers.LeftAlt,"Alt",0xE2), (ShortcutModifiers.RightAlt,"RightAlt",0xE6),
        (ShortcutModifiers.LeftWin,"Win",0xE3), (ShortcutModifiers.RightWin,"RightWin",0xE7)];
    public static ImmutableDictionary<string, byte> Keys { get; } = BuildKeys();
    private static ImmutableDictionary<string, byte> BuildKeys()
    {
        var keys=new Dictionary<string,byte>(StringComparer.OrdinalIgnoreCase);
        for(int i=0;i<26;i++) keys[((char)('A'+i)).ToString()]=(byte)(4+i);
        for(int i=1;i<=9;i++) keys[i.ToString()]=(byte)(29+i); keys["0"]=0x27;
        for(int i=1;i<=24;i++) keys["F"+i]=(byte)(i<=12?0x39+i:0x68+i-13);
        string[] names=["Enter","Escape","Backspace","Tab","Space","Minus","Equal","LeftBracket","RightBracket","Backslash","NonUsHash","Semicolon","Quote","Backquote","Comma","Period","Slash","CapsLock"];
        for(int i=0;i<names.Length;i++) keys[names[i]]=(byte)(0x28+i);
        string[] nav=["PrintScreen","ScrollLock","Pause","Insert","Home","PageUp","Delete","End","PageDown","Right","Left","Down","Up","NumLock","NumDivide","NumMultiply","NumSubtract","NumAdd","NumEnter","Num1","Num2","Num3","Num4","Num5","Num6","Num7","Num8","Num9","Num0","NumDecimal"];
        for(int i=0;i<nav.Length;i++) keys[nav[i]]=(byte)(0x46+i);
        return keys.ToImmutableDictionary(StringComparer.OrdinalIgnoreCase);
    }
    public string Canonical => string.Join("+",ModifierOrder.Where(x=>Modifiers.HasFlag(x.Flag)).Select(x=>x.Name).Append(Key));
    public string Display => Canonical.Replace("+"," + ");
    public byte BaseHid => Keys.TryGetValue(Key,out var value)?value:throw new ArgumentException("Invalid shortcut key.");
    public int HostValue => (int)Modifiers | BaseHid;
    public byte[] HidSequence => ModifierOrder.Where(x=>Modifiers.HasFlag(x.Flag)).Select(x=>x.Hid).Append(BaseHid).ToArray();
    public static bool TryParse(string? text, out ShortcutGesture? gesture)
    {
        gesture=null; if(string.IsNullOrWhiteSpace(text)) return false;
        var parts=text.Split('+',StringSplitOptions.TrimEntries); var modifiers=ShortcutModifiers.None;
        for(int i=0;i<parts.Length-1;i++)
        {
            var part=parts[i].StartsWith("Left",StringComparison.OrdinalIgnoreCase)?parts[i][4..]:parts[i];
            var match=ModifierOrder.FirstOrDefault(x=>x.Name.Equals(part,StringComparison.OrdinalIgnoreCase));
            if(match.Flag==ShortcutModifiers.None || modifiers.HasFlag(match.Flag)) return false; modifiers|=match.Flag;
        }
        var key=Keys.Keys.FirstOrDefault(x=>x.Equals(parts[^1],StringComparison.OrdinalIgnoreCase));
        if(key is null) return false; gesture=new(modifiers,key); return true;
    }
}
// UI-independent capture state; the WPF adapter supplies only local focused key events.
public sealed class ShortcutCapture
{
    public bool IsRecording { get; private set; }
    public ShortcutModifiers Modifiers { get; private set; }
    public void Start() { IsRecording=true; Modifiers=ShortcutModifiers.None; }
    public void Cancel() { IsRecording=false; Modifiers=ShortcutModifiers.None; }
    public void UpdateModifiers(ShortcutModifiers modifiers) { if(IsRecording) Modifiers=modifiers; }
    public ShortcutGesture? Press(string? key, ShortcutModifiers modifiers)
    {
        if(!IsRecording) return null; Modifiers=modifiers;
        if(key is null || !ShortcutGesture.Keys.ContainsKey(key)) return null;
        var result=new ShortcutGesture(modifiers,key); Cancel(); return result;
    }
}
public static class DeviceLabelRules
{
    public static bool IsValid(string label) => label.Length<=20 && label.All(c=>c is >= ' ' and <= '~');
}

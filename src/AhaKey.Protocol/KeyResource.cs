using AhaKey.Core;
namespace AhaKey.Protocol;

// Resource 0 is the live 100-byte key payload, not its separate ASCII label.
public static class KeyResource
{
    public static ShortcutGesture? Shortcut(ReadOnlySpan<byte> bytes)
    {
        if(bytes.Length!=100)throw new FormatException("Expected 100-byte key resource.");
        if(bytes[0]!=0x73||bytes[1] is <1 or >9)return null;
        var modifiers=ShortcutModifiers.None;string? key=null;
        foreach(byte code in bytes.Slice(2,bytes[1]))
        {
            var modifier=ShortcutGesture.ModifierOrder.FirstOrDefault(m=>m.Hid==code);
            if(modifier.Flag!=ShortcutModifiers.None){if(modifiers.HasFlag(modifier.Flag))return null;modifiers|=modifier.Flag;}
            else {if(key is not null)return null;key=ShortcutGesture.Keys.FirstOrDefault(k=>k.Value==code).Key;if(key is null)return null;}
        }
        return key is null?null:new(modifiers,key);
    }
}

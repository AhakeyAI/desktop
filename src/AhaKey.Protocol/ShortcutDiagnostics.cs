using AhaKey.Core;
namespace AhaKey.Protocol;
// Source-derived normal Windows save order (D); never used as a transport.
public static class ShortcutDiagnostics
{
    public static byte[] Preview(HardwareProfileId profile, PhysicalKey key, KeyboardShortcutAction action)
    {
        if(!Enum.IsDefined(profile) || key is not (PhysicalKey.K2 or PhysicalKey.K3 or PhysicalKey.K4) || !ShortcutGesture.TryParse(action.Shortcut,out var gesture))
            throw new ArgumentException("Only K2-K4 shortcuts have a normal-save preview.");
        return [0xAA,0xBB,0x73,0x73,(byte)profile,(byte)key,..gesture!.HidSequence,0xCC,0xDD];
    }
}

using System.Collections.Immutable;
namespace AhaKey.Core;

public readonly record struct HostKey(byte VirtualKey,bool Extended=false);
// Host-side virtual keys, deliberately separate from device HID shortcut encoding.
public static class HostShortcutPlan
{
    public static ImmutableArray<HostKey> Create(string text)
    {
        if(!ShortcutGesture.TryParse(text,out var gesture)||gesture!.Key=="F18")throw new ArgumentException("Invalid or recursive F18 action.");
        var keys=ImmutableArray.CreateBuilder<HostKey>();
        foreach(var m in ShortcutGesture.ModifierOrder.Where(x=>gesture.Modifiers.HasFlag(x.Flag)))
            keys.Add(m.Flag switch
            {
                ShortcutModifiers.LeftCtrl=>new(0xA2),ShortcutModifiers.RightCtrl=>new(0xA3,true),
                ShortcutModifiers.LeftShift=>new(0xA0),ShortcutModifiers.RightShift=>new(0xA1),
                ShortcutModifiers.LeftAlt=>new(0xA4),ShortcutModifiers.RightAlt=>new(0xA5,true),
                ShortcutModifiers.LeftWin=>new(0x5B,true),ShortcutModifiers.RightWin=>new(0x5C,true),_=>throw new ArgumentException()
            });
        byte h=gesture.BaseHid;
        keys.Add(h switch
        {
            >=4 and <=29=>new((byte)(0x41+h-4)),>=30 and <=38=>new((byte)(0x31+h-30)),0x27=>new(0x30),
            >=0x3A and <=0x45=>new((byte)(0x70+h-0x3A)),>=0x68 and <=0x73=>new((byte)(0x7C+h-0x68)),
            0x28=>new(0x0D),0x29=>new(0x1B),0x2A=>new(8),0x2B=>new(9),0x2C=>new(0x20),
            0x2D=>new(0xBD),0x2E=>new(0xBB),0x2F=>new(0xDB),0x30=>new(0xDD),0x31=>new(0xDC),
            0x33=>new(0xBA),0x34=>new(0xDE),0x35=>new(0xC0),0x36=>new(0xBC),0x37=>new(0xBE),0x38=>new(0xBF),0x39=>new(0x14),
            0x46=>new(0x2C,true),0x47=>new(0x91),0x48=>new(0x13),0x49=>new(0x2D,true),0x4A=>new(0x24,true),0x4B=>new(0x21,true),
            0x4C=>new(0x2E,true),0x4D=>new(0x23,true),0x4E=>new(0x22,true),0x4F=>new(0x27,true),0x50=>new(0x25,true),0x51=>new(0x28,true),0x52=>new(0x26,true),
            0x53=>new(0x90,true),0x54=>new(0x6F,true),0x55=>new(0x6A),0x56=>new(0x6D),0x57=>new(0x6B),0x58=>new(0x0D,true),
            >=0x59 and <=0x61=>new((byte)(0x61+h-0x59)),0x62=>new(0x60),0x63=>new(0x6E),
            _=>throw new ArgumentException("This physical key has no unambiguous Windows virtual-key mapping.")
        });
        return keys.ToImmutable();
    }
}

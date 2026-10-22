using System.Windows.Input;
using AhaKey.Core;
namespace AhaKey.Studio.Services;
// Mapping only. No native hooks, SendInput, virtual keyboard, or transport APIs.
public static class LocalShortcutInput
{
    public static Key ActualKey(KeyEventArgs e) => e.Key==Key.System?e.SystemKey:e.Key==Key.ImeProcessed?e.ImeProcessedKey:e.Key;
    public static bool IsModifier(Key key) => key is Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift or Key.LeftAlt or Key.RightAlt or Key.LWin or Key.RWin;
    public static string? Name(Key key)
    {
        if(key>=Key.A && key<=Key.Z) return key.ToString();
        if(key>=Key.D0 && key<=Key.D9) return ((int)key-(int)Key.D0).ToString();
        if(key>=Key.NumPad0 && key<=Key.NumPad9) return "Num"+((int)key-(int)Key.NumPad0);
        if(key>=Key.F1 && key<=Key.F24) return key.ToString();
        return key switch { Key.Return=>"Enter", Key.Escape=>"Escape",Key.Back=>"Backspace",Key.Tab=>"Tab",Key.Space=>"Space",Key.OemMinus=>"Minus",Key.OemPlus=>"Equal",Key.OemOpenBrackets=>"LeftBracket",Key.OemCloseBrackets=>"RightBracket",Key.OemPipe=>"Backslash",Key.OemSemicolon=>"Semicolon",Key.OemQuotes=>"Quote",Key.OemTilde=>"Backquote",Key.OemComma=>"Comma",Key.OemPeriod=>"Period",Key.OemQuestion=>"Slash",Key.Capital=>"CapsLock",Key.Snapshot=>"PrintScreen",Key.Scroll=>"ScrollLock",Key.Pause=>"Pause",Key.Insert=>"Insert",Key.Home=>"Home",Key.Prior=>"PageUp",Key.Delete=>"Delete",Key.End=>"End",Key.Next=>"PageDown",Key.Right=>"Right",Key.Left=>"Left",Key.Down=>"Down",Key.Up=>"Up",Key.NumLock=>"NumLock",Key.Divide=>"NumDivide",Key.Multiply=>"NumMultiply",Key.Subtract=>"NumSubtract",Key.Add=>"NumAdd",Key.Decimal=>"NumDecimal",_=>null };
    }
    public static ShortcutModifiers Modifiers()
    {
        var result=ShortcutModifiers.None;
        foreach(var (key,flag) in new[] {(Key.LeftCtrl,ShortcutModifiers.LeftCtrl),(Key.RightCtrl,ShortcutModifiers.RightCtrl),(Key.LeftShift,ShortcutModifiers.LeftShift),(Key.RightShift,ShortcutModifiers.RightShift),(Key.LeftAlt,ShortcutModifiers.LeftAlt),(Key.RightAlt,ShortcutModifiers.RightAlt),(Key.LWin,ShortcutModifiers.LeftWin),(Key.RWin,ShortcutModifiers.RightWin)}) if(Keyboard.IsKeyDown(key)) result|=flag;
        return result;
    }
}

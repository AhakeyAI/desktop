using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using AhaKey.Core;
using AhaKey.Services;
namespace AhaKey.Studio.Services;

// F18 key-down only; no assumed hold/release semantics and no microphone implementation.
public sealed class VoiceRoutingRuntime(LocalDeviceProjectStore projects):IDisposable
{
    private VoiceRoutingSettings? configured;
    private bool suspended;
    public void Suspend(bool value){suspended=value;configured=null;Configure();}
    private HwndSource? source;private bool registered;private const int HotkeyId=0xA18;
    public string? ErrorKey {get;private set;}
    public DateTimeOffset? LastDetectedAt {get;private set;}
    public event Action? Changed;
    public void Attach(Window window)
    {source=HwndSource.FromHwnd(new WindowInteropHelper(window).Handle);source?.AddHook(Hook);projects.Changed+=Configure;Configure();}
    public void Configure()
    {
        if(source is null)return;if(!source.Dispatcher.CheckAccess()){source.Dispatcher.BeginInvoke(Configure);return;}
        if(configured==projects.Current?.Voice)return;configured=projects.Current?.Voice;
        if(registered){UnregisterHotKey(source.Handle,HotkeyId);registered=false;}
        ErrorKey=null;
        if(!suspended&&projects.Current?.Voice is {Enabled:true,Action:not VoiceHostAction.None} voice)
        {
            if(voice.Action==VoiceHostAction.LocalShortcut&&string.IsNullOrWhiteSpace(voice.Shortcut)||voice.Action==VoiceHostAction.ActivateApplication&&string.IsNullOrWhiteSpace(voice.ApplicationPath)){ErrorKey="VoiceActionFailed";Changed?.Invoke();return;}
            registered=RegisterHotKey(source.Handle,HotkeyId,0x4000,0x81);if(!registered)ErrorKey="VoiceHotkeyUnavailable";}
        Changed?.Invoke();
    }
    private IntPtr Hook(IntPtr hwnd,int msg,IntPtr wParam,IntPtr lParam,ref bool handled)
    {
        if(msg!=0x0312||wParam.ToInt32()!=HotkeyId)return IntPtr.Zero;
        handled=true;LastDetectedAt=DateTimeOffset.UtcNow;
        TestAction();return IntPtr.Zero;
    }
    public void TestAction()
    {
        try
        {
            var config=projects.Current!.Voice;
            if(!config.Enabled)return;
            if(config.Action==VoiceHostAction.WindowsVoiceTyping)SendShortcut("Win+H");
            else if(config.Action==VoiceHostAction.LocalShortcut && config.Shortcut is {} shortcut)SendShortcut(shortcut);
            else if(config.Action==VoiceHostAction.ActivateApplication && config.ApplicationPath is {} path)
            {
                if(!System.IO.File.Exists(path)||!path.EndsWith(".exe",StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException();
                var match=Process.GetProcessesByName(System.IO.Path.GetFileNameWithoutExtension(path)).FirstOrDefault(p=>p.MainWindowHandle!=IntPtr.Zero && SameExecutable(p,path));
                if(match is not null){ShowWindow(match.MainWindowHandle,9);SetForegroundWindow(match.MainWindowHandle);match.Dispose();}
                else Process.Start(new ProcessStartInfo(path){UseShellExecute=false});
            }
            ErrorKey=null;
        }
        catch(Exception ex)when(ex is not OutOfMemoryException){ErrorKey="VoiceActionFailed";}
        Changed?.Invoke();
    }
    private static bool SameExecutable(Process process,string path){try{return string.Equals(process.MainModule?.FileName,path,StringComparison.OrdinalIgnoreCase);}catch{return false;}}
    private static void SendShortcut(string text)
    {
        var keys=HostShortcutPlan.Create(text);
        try{foreach(var key in keys)keybd_event(key.VirtualKey,0,key.Extended?1u:0u,UIntPtr.Zero);}
        finally{foreach(var key in keys.Reverse())keybd_event(key.VirtualKey,0,(key.Extended?1u:0u)|2u,UIntPtr.Zero);}
    }

    public void Dispose(){projects.Changed-=Configure;if(source is not null){if(registered)UnregisterHotKey(source.Handle,HotkeyId);source.RemoveHook(Hook);}}
    [DllImport("user32.dll")]private static extern bool RegisterHotKey(IntPtr hwnd,int id,uint modifiers,uint key);
    [DllImport("user32.dll")]private static extern bool UnregisterHotKey(IntPtr hwnd,int id);
    [DllImport("user32.dll")]private static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
    [DllImport("user32.dll")]private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")]private static extern bool ShowWindow(IntPtr window,int command);
}

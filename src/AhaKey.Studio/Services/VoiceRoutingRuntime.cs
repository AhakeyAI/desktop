using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using AhaKey.Core;
using AhaKey.Services;
namespace AhaKey.Studio.Services;

// Opt-in Windows F18 routing. Native down/up required for duration; injected input is ignored.
public sealed class VoiceRoutingRuntime(LocalDeviceProjectStore projects):IDisposable
{
    private VoiceRoutingSettings? configured;private Guid? configuredProject;private bool disposed;
    private bool suspended;private IntPtr keyboardHook;private LowLevelKeyboardProc? keyboardCallback;
    private readonly VoicePressTracker press=new();private long contextGeneration;
    private IntPtr downWindow;private IntPtr foregroundHook;private WinEventProc? foregroundCallback;
    private delegate void WinEventProc(IntPtr hook,uint evt,IntPtr window,int obj,int child,uint thread,uint time);
    private delegate IntPtr LowLevelKeyboardProc(int code,IntPtr message,IntPtr data);
    [StructLayout(LayoutKind.Sequential)]private struct KeyboardData {public uint Key,Scan,Flags,Time;public UIntPtr Extra;}
    private void CancelPress(){press.Cancel();contextGeneration++;}
    private void SessionChanged(object sender,Microsoft.Win32.SessionSwitchEventArgs e)=>source?.Dispatcher.BeginInvoke(CancelPress);

    public void Suspend(bool value){suspended=value;configured=null;Configure();}
    private HwndSource? source;private bool registered;private const int HotkeyId=0xA18;
    public string? ErrorKey {get;private set;}
    public DateTimeOffset? LastDetectedAt {get;private set;}
    public event Action? Changed;
    public void Attach(Window window)
    {source=HwndSource.FromHwnd(new WindowInteropHelper(window).Handle);source?.AddHook(Hook);projects.Changed+=Configure;Microsoft.Win32.SystemEvents.SessionSwitch+=SessionChanged;Configure();}
    public void Configure()
    {
        if(disposed||source is null)return;if(!source.Dispatcher.CheckAccess()){source.Dispatcher.BeginInvoke(Configure);return;}
        if(configured==projects.Current?.Voice&&configuredProject==projects.Current?.Id)return;configuredProject=projects.Current?.Id;configured=projects.Current?.Voice;CancelPress();
        if(keyboardHook!=IntPtr.Zero){UnhookWindowsHookEx(keyboardHook);keyboardHook=IntPtr.Zero;}
        if(foregroundHook!=IntPtr.Zero){UnhookWinEvent(foregroundHook);foregroundHook=IntPtr.Zero;}
        if(registered){UnregisterHotKey(source.Handle,HotkeyId);registered=false;}
        ErrorKey=null;
        if(!suspended&&projects.Current?.Voice is {Enabled:true} voice && (voice.Action!=VoiceHostAction.None||voice.ShortLongEnabled&&voice.LongAction!=VoiceHostAction.None))
        {
            if(voice.Action==VoiceHostAction.LocalShortcut&&string.IsNullOrWhiteSpace(voice.Shortcut)||voice.Action==VoiceHostAction.ActivateApplication&&string.IsNullOrWhiteSpace(voice.ApplicationPath)){ErrorKey="VoiceActionFailed";Changed?.Invoke();return;}
            if(voice.ShortLongEnabled)
            {
                keyboardCallback=KeyboardEvent;
                keyboardHook=SetWindowsHookEx(13,keyboardCallback,GetModuleHandle(null),0);
                foregroundCallback=(_,_,_,_,_,_,_)=>CancelPress();
                foregroundHook=SetWinEventHook(3,3,IntPtr.Zero,foregroundCallback,0,0,0);
                if(keyboardHook==IntPtr.Zero||foregroundHook==IntPtr.Zero){ErrorKey="VoiceHotkeyUnavailable";if(keyboardHook!=IntPtr.Zero){UnhookWindowsHookEx(keyboardHook);keyboardHook=IntPtr.Zero;}}
            }
            else {registered=RegisterHotKey(source.Handle,HotkeyId,0x4000,0x81);if(!registered)ErrorKey="VoiceHotkeyUnavailable";}}
        Changed?.Invoke();
    }
    private IntPtr Hook(IntPtr hwnd,int msg,IntPtr wParam,IntPtr lParam,ref bool handled)
    {
        if(disposed||msg!=0x0312||wParam.ToInt32()!=HotkeyId)return IntPtr.Zero;
        handled=true;LastDetectedAt=DateTimeOffset.UtcNow;
        TestAction();return IntPtr.Zero;
    }
    private IntPtr KeyboardEvent(int code,IntPtr message,IntPtr data)
    {
        if(!disposed&&code>=0&&!suspended&&configured is {Enabled:true,ShortLongEnabled:true} config)
        {
            var key=Marshal.PtrToStructure<KeyboardData>(data);int msg=message.ToInt32();
            if(key.Key==0x81&&(key.Flags&0x10)==0)
            {
                if(msg is 0x100 or 0x104)
                {if(press.KeyDown(Environment.TickCount64,contextGeneration))downWindow=GetForegroundWindow();}
                else if(msg is 0x101 or 0x105)
                {
                    if(downWindow!=GetForegroundWindow())CancelPress();
                    var result=press.KeyUp(Environment.TickCount64,contextGeneration,config.LongPressMilliseconds);
                    if(result is {} action)
                    {
                        long generation=contextGeneration;
                        source?.Dispatcher.BeginInvoke(()=>{if(disposed||generation!=contextGeneration||suspended||configured!=config)return;LastDetectedAt=DateTimeOffset.UtcNow;ExecuteAction(action==VoicePress.Long?config with{Action=config.LongAction,Shortcut=config.LongShortcut,ApplicationPath=config.LongApplicationPath}:config);});
                    }
                }
            }
        }
        return CallNextHookEx(keyboardHook,code,message,data);
    }
    public void TestAction()=>ExecuteAction(projects.Current?.Voice);
    private void ExecuteAction(VoiceRoutingSettings? config)
    {
        try
        {
            if(disposed||config?.Enabled!=true)return;
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

    public void Dispose(){if(disposed)return;disposed=true;CancelPress();Microsoft.Win32.SystemEvents.SessionSwitch-=SessionChanged;if(keyboardHook!=IntPtr.Zero){UnhookWindowsHookEx(keyboardHook);keyboardHook=IntPtr.Zero;}
        if(foregroundHook!=IntPtr.Zero){UnhookWinEvent(foregroundHook);foregroundHook=IntPtr.Zero;}projects.Changed-=Configure;if(source is not null){if(registered)UnregisterHotKey(source.Handle,HotkeyId);source.RemoveHook(Hook);}}
    [DllImport("user32.dll")]private static extern IntPtr SetWinEventHook(uint min,uint max,IntPtr module,WinEventProc callback,uint process,uint thread,uint flags);
    [DllImport("user32.dll")]private static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("user32.dll",SetLastError=true)]private static extern IntPtr SetWindowsHookEx(int id,LowLevelKeyboardProc callback,IntPtr module,uint thread);
    [DllImport("user32.dll")]private static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")]private static extern IntPtr CallNextHookEx(IntPtr hook,int code,IntPtr message,IntPtr data);
    [DllImport("user32.dll")]private static extern IntPtr GetForegroundWindow();
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]private static extern IntPtr GetModuleHandle(string? name);
    [DllImport("user32.dll")]private static extern bool RegisterHotKey(IntPtr hwnd,int id,uint modifiers,uint key);
    [DllImport("user32.dll")]private static extern bool UnregisterHotKey(IntPtr hwnd,int id);
    [DllImport("user32.dll")]private static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
    [DllImport("user32.dll")]private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")]private static extern bool ShowWindow(IntPtr window,int command);
}

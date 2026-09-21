using Microsoft.Win32;
namespace AhaKey.Studio.Services;

public static class WindowsStartup
{
    private const string Key = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string Name = "AhaKeyStudio";
    public static bool Enabled
    {
        get { using var key=Registry.CurrentUser.OpenSubKey(Key);return key?.GetValue(Name) is string; }
    }
    public static void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(Key);
        if (enabled)
        {
            var exe = Environment.ProcessPath ?? throw new InvalidOperationException("Application path unavailable.");
            key.SetValue(Name, "\"" + exe + "\" --tray", RegistryValueKind.String);
        }
        else key.DeleteValue(Name, false);
    }
}

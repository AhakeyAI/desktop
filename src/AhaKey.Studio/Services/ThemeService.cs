using System.Windows;
using AhaKey.Services;
using Microsoft.Win32;
namespace AhaKey.Studio.Services;
public sealed class ThemeService : IDisposable
{
    private ResourceDictionary? active;
    public ThemeChoice Choice { get; private set; }
    public string EffectiveTheme { get; private set; } = "Light";
    public ThemeService() => SystemEvents.UserPreferenceChanged += OnPreferenceChanged;
    public void Apply(ThemeChoice choice)
    {
        Choice = choice;
        var dark = choice == ThemeChoice.Dark || choice == ThemeChoice.System && IsSystemDark();
        EffectiveTheme = dark ? "Dark" : "Light";
        var next = new ResourceDictionary { Source = new Uri($"Themes/{EffectiveTheme}.xaml", UriKind.Relative) };
        var resources = Application.Current.Resources.MergedDictionaries;
        if (active is not null) resources.Remove(active);
        resources.Insert(0, next); active = next;
    }
    private static bool IsSystemDark()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue("AppsUseLightTheme") is int value && value == 0;
    }
    private void OnPreferenceChanged(object sender, UserPreferenceChangedEventArgs args)
    { if (Choice == ThemeChoice.System) Application.Current.Dispatcher.BeginInvoke(() => Apply(Choice)); }
    public void Dispose() => SystemEvents.UserPreferenceChanged -= OnPreferenceChanged;
}

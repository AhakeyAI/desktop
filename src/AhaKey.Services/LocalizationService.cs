using System.ComponentModel;
using System.Globalization;
using System.Resources;
namespace AhaKey.Services;
public sealed class LocalizationService : INotifyPropertyChanged
{
    private readonly ResourceManager resources = new("AhaKey.Services.Resources.Strings", typeof(LocalizationService).Assembly);
    public CultureInfo Culture { get; private set; } = CultureInfo.GetCultureInfo("en");
    public event PropertyChangedEventHandler? PropertyChanged;
    public string this[string key] => resources.GetString(key, Culture) ?? $"[{key}]";
    public void Apply(LanguageChoice choice)
    {
        var system = CultureInfo.InstalledUICulture;
        var name = choice switch { LanguageChoice.English => "en", LanguageChoice.Russian => "ru", LanguageChoice.Chinese => "zh-CN",
            _ => SystemCultureName(system.Name) };
        Culture = CultureInfo.GetCultureInfo(name);
        CultureInfo.CurrentUICulture = Culture; CultureInfo.DefaultThreadCurrentUICulture = Culture;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs("Item[]"));
    }
    public static string SystemCultureName(string name)=>name.StartsWith("ru",StringComparison.OrdinalIgnoreCase)?"ru":name.StartsWith("zh",StringComparison.OrdinalIgnoreCase)?"zh-CN":"en";
}

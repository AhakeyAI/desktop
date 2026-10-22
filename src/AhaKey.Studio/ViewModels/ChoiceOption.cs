using AhaKey.Services;
using CommunityToolkit.Mvvm.ComponentModel;
namespace AhaKey.Studio.ViewModels;
public sealed class ChoiceOption<T> : ObservableObject
{
    private readonly LocalizationService localization;
    public T Value { get; }
    public string Key { get; }
    public string Label => localization[Key];
    public ChoiceOption(T value, string key, LocalizationService localization)
    { Value = value; Key = key; this.localization = localization; localization.PropertyChanged += (_, _) => OnPropertyChanged(nameof(Label)); }
}

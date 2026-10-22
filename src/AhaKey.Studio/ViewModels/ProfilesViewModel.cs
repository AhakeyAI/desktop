using System.IO;
using AhaKey.Core;
using AhaKey.Services;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
namespace AhaKey.Studio.ViewModels;
public sealed partial class ProfileCardViewModel : ObservableObject
{
    public Profile Profile { get; private set; }
    private readonly LocalizationService l;
    private readonly ProfileSelectionService preferences;
    public string Name => Profile.HardwareProfileId == HardwareProfileId.Custom ? preferences.Settings.CustomProfileName ?? l["Custom"] : l[Profile.ProfileType.ToString()];
    public string IconKind => Profile.ProfileType.ToString();
    public string IntegrationName => Profile.IntegrationId is null ? l["NoIntegration"] : l[Profile.ProfileType.ToString()];
    public string Description => l[Profile.ProfileType + "Description"];
    public LocalizationService L => l;
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(AccessibleName))] private bool selected;
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(SelectorName))] [NotifyPropertyChangedFor(nameof(AccessibleName))] private bool isDirty;
    public string AccessibleName=>SelectorName+(Selected?" · "+L["ProductEditing"]:"");
    public string SelectorName => IsDirty ? Name + " · " + L["PhysicalLocalOnly"] : Name;
    public ProfileCardViewModel(Profile profile, LocalizationService l, ProfileSelectionService preferences)
    { Profile = profile; this.l = l; this.preferences = preferences; l.PropertyChanged += (_, _) => Refresh(); }
    public void Refresh() { OnPropertyChanged(nameof(AccessibleName)); OnPropertyChanged(nameof(Name)); OnPropertyChanged(nameof(SelectorName)); OnPropertyChanged(nameof(Description)); OnPropertyChanged(nameof(IntegrationName)); }
}
public sealed partial class ProfilesViewModel : ObservableObject
{
    private readonly ProfileSelectionService preferences;
    private readonly Services.ProfileActivationRuntime? activation;
    public LocalizationService L { get; }
    public IReadOnlyList<ProfileCardViewModel> Cards { get; }
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(HasSelection))] [NotifyPropertyChangedFor(nameof(IsFirstRun))] private ProfileCardViewModel? selected;
    [ObservableProperty] private string customName;
    [ObservableProperty] private string? errorKey;
    public bool HasSelection => Selected is not null;
    public bool IsFirstRun => Selected is null;
    public ProfilesViewModel(ProfileSelectionService preferences, LocalizationService l,Services.ProfileActivationRuntime? activation=null)
    {
        this.preferences = preferences; this.activation=activation; L = l;
        Cards = Profile.Defaults.Select(p => new ProfileCardViewModel(p, l, preferences)).ToArray();
        selected = Cards.SingleOrDefault(p => p.Profile.HardwareProfileId == preferences.Settings.SelectedProfile);
        if (selected is not null) selected.Selected = true;
        customName = preferences.Settings.CustomProfileName ?? l["Custom"];
        preferences.Changed+=()=>{foreach(var card in Cards)card.Refresh();CustomName=preferences.Settings.CustomProfileName??l["Custom"];};
        var priorDefault = l["Custom"];
        l.PropertyChanged += (_, _) =>
        {
            if (preferences.Settings.CustomProfileName is null && CustomName == priorDefault) CustomName = l["Custom"];
            priorDefault = l["Custom"];
        };
    }
    partial void OnSelectedChanged(ProfileCardViewModel? value)
    {
        if (value is null) return;
        try { preferences.Select(value.Profile.HardwareProfileId); ErrorKey = null; }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { ErrorKey = "SettingsSaveError"; }
        foreach (var card in Cards) card.Selected = card == value;
        if(activation is not null && activation.Enabled)_=activation.ActivateAsync(value.Profile.HardwareProfileId);
    }
    [RelayCommand] private void Select(ProfileCardViewModel card) => Selected = card;
    [RelayCommand] private void Rename()
    {
        try { preferences.RenameCustom(CustomName); Cards[3].Refresh(); ErrorKey = null; }
        catch (ArgumentException) { ErrorKey = "NameInvalid"; }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { ErrorKey = "SettingsSaveError"; }
    }
}

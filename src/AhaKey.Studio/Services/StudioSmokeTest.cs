using System.IO;
using System.Windows.Input;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Services;
using AhaKey.Studio.ViewModels;
using AhaKey.Studio.Views;
using AhaKey.Studio.Controls;
using Microsoft.Extensions.DependencyInjection;
namespace AhaKey.Studio.Services;
// Opt-in software acceptance harness; uses the actual WPF window and an isolated settings root.
public static class StudioSmokeTest
{
    public static async Task RunAsync(Window window, IServiceProvider services, string output)
    {
        Directory.CreateDirectory(output);
        var vm = services.GetRequiredService<ShellViewModel>();
        var preferences = services.GetRequiredService<ProfileSelectionService>();
        var store = services.GetRequiredService<SettingsStore>();
        var checks = new List<string>();
        void Check(bool condition, string name) { if (!condition) throw new InvalidOperationException("Smoke assertion: " + name); checks.Add(name); }
        Check(vm.Profiles.IsFirstRun, "First run opens Home with no selected profile");
        Check(vm.Page == PageId.Home && vm.Manager.State == ConnectionState.Disconnected, "No automatic device connection");
        vm.Settings.Language = vm.Settings.Languages.Single(x => x.Value == LanguageChoice.English);
        vm.Settings.Theme = vm.Settings.Themes.Single(x => x.Value == ThemeChoice.Light);
        await Capture(window, output, "home-first-run");
        vm.Profiles.SelectCommand.Execute(vm.Profiles.Cards[2]);
        Check(new ProfileSelectionService(new SettingsStore(store.Root)).Settings.SelectedProfile == HardwareProfileId.Codex, "Profile survives a new settings service instance");
        await vm.ConnectCommand.ExecuteAsync(null);
        Check(vm.Manager.State == ConnectionState.Connected && vm.Manager.Tracker.State == SyncState.Synced, "Mock connect and read");
        await Capture(window, output, "home-light");
        vm.Settings.Theme = vm.Settings.Themes.Single(x => x.Value == ThemeChoice.Dark);
        await Capture(window, output, "home-dark");
        Check(window.Title == "AhaKey Studio" && window.Icon is not null, "Product branding uses supplied application icon");
        Check(DevicePreview.Regions.Count == 7 && DevicePreview.Regions.Select(x => x.Id).Distinct().Count() == 7, "Seven distinct future hardware regions");
        Check(DevicePreview.Regions.All(x => new Rect(0,0,920,520).Contains(x.Bounds)), "Hardware regions fit the reference photo crop");
        vm.NavigationSelection = vm.Navigation.Single(x => x.Value == PageId.Keymap);
        await Capture(window, output, "device-preview-dark");
        Check(Descendants(window).OfType<DevicePreview>().Any(x => x.IsVisible), "Keymap presents the current hardware reference");
        vm.Settings.Theme = vm.Settings.Themes.Single(x => x.Value == ThemeChoice.Light);
        await Capture(window, output, "device-preview-light");
        vm.Settings.Theme = vm.Settings.Themes.Single(x => x.Value == ThemeChoice.Dark);
        vm.OpenSettingsCommand.Execute(null); await Capture(window, output, "settings");
        var combo = Descendants(window).OfType<ComboBox>().First();
        Check(combo.Focus(), "Profile selector can receive keyboard focus");
        combo.IsDropDownOpen = true; await Settle(window);
        Check(combo.IsDropDownOpen, "Profile dropdown opens"); combo.IsDropDownOpen = false;
        Check(combo.MoveFocus(new TraversalRequest(FocusNavigationDirection.Next)), "Keyboard tab traversal works");
        foreach (var language in new[] { LanguageChoice.English, LanguageChoice.Russian, LanguageChoice.Chinese })
        {
            vm.Settings.Language = vm.Settings.Languages.Single(x => x.Value == language);
            foreach (var page in vm.Navigation) { vm.NavigationSelection = page; await Settle(window); ValidateVisibleText(window); Check(vm.Page == page.Value, $"Navigation {language}/{page.Value}"); }
            vm.NavigationSelection = vm.Navigation[0];
            if (language == LanguageChoice.Russian)
            {
                window.Width = 1024; window.Height = 900;
                await Capture(window, output, "home-ru-1024");
                vm.OpenSettingsCommand.Execute(null); await Capture(window, output, "settings-ru-1024");
            }
            if (language == LanguageChoice.Chinese)
            {
                window.Width = 1200; vm.Settings.Theme = vm.Settings.Themes.Single(x => x.Value == ThemeChoice.Light);
                await Capture(window, output, "home-zh");
                vm.OpenSettingsCommand.Execute(null); await Capture(window, output, "settings-zh");
            }
            var dialog = new AboutDialog(vm.L) { Owner = window }; dialog.Show(); await Capture(dialog, output, $"dialog-{language}"); dialog.Close();
        }
        vm.Settings.Language = vm.Settings.Languages.Single(x => x.Value == LanguageChoice.English);
        vm.NavigationSelection = vm.Navigation.Single(x => x.Value == PageId.Display);
        await Capture(window, output, "display");
        Check(vm.DisplayPlanner.Assets.Count==4 && vm.DisplayPlanner.Plan is null && vm.DisplayPlanner.Preview is null,"Empty Display planner does not invent uploaded assets; four asset states available");
        Check(Enum.GetValues<DisplayState>().Select(DisplayLimits.MaximumFrames).SequenceEqual(new[]{8,12,12,12}),"Display planner retains 8/12/12/12 software proposal limits");
        window.Width=1024; await Capture(window, output, "display-1024");
        vm.Settings.Theme = vm.Settings.Themes.Single(x => x.Value == ThemeChoice.Dark);
        await Capture(window, output, "display-dark");
        vm.Settings.Theme = vm.Settings.Themes.Single(x => x.Value == ThemeChoice.Light);
        vm.NavigationSelection = vm.Navigation.Single(x => x.Value == PageId.Lighting);
        vm.Brightness = 64; Check(vm.Manager.Tracker.State == SyncState.UnsavedChanges, "Global mock draft dirty");
        await vm.WriteCommand.ExecuteAsync(null); Check(vm.Manager.Tracker.State == SyncState.WriteAccepted, "Write accepted remains distinct from readback");
        await vm.ReadCommand.ExecuteAsync(null); Check(vm.Manager.Tracker.State == SyncState.Synced, "Explicit mock readback");
        vm.Profiles.CustomName = "VS Code"; vm.Profiles.RenameCommand.Execute(null);
        Check(vm.Profiles.Cards[3].Name == "VS Code" && (int)vm.Profiles.Cards[3].Profile.HardwareProfileId == 3, "Local rename preserves slot");
        vm.Profiles.CustomName = " "; vm.Profiles.RenameCommand.Execute(null); Check(vm.HasError, "Invalid rename surfaced");
        vm.Profiles.CustomName = "VS Code"; vm.Profiles.RenameCommand.Execute(null);
        vm.Settings.Backend = vm.Settings.Backends.Single(x => x.Value == BackendChoice.Real); await vm.Settings.BackendChange;
        await vm.Manager.ConnectAsync(); Check(vm.Manager.RealBackendSelected && vm.Manager.State == ConnectionState.Disconnected && !vm.CanWrite, "Real unavailable with no mock fallback");
        vm.OpenSettingsCommand.Execute(null); await Capture(window, output, "real-unavailable");
        vm.Settings.Backend = vm.Settings.Backends.Single(x => x.Value == BackendChoice.Mock); await vm.Settings.BackendChange;
        await vm.ConnectCommand.ExecuteAsync(null);
        vm.NavigationSelection = vm.Navigation.Single(x => x.Value == PageId.Diagnostics);
        vm.Failure = vm.Failures.Single(x => x.Value == MockFailure.Timeout); vm.ArmFailureCommand.Execute(null);
        await vm.WriteCommand.ExecuteAsync(null); Check(vm.Manager.Tracker.State == SyncState.Indeterminate && vm.HasError, "Timeout surfaced as indeterminate");
        await Capture(window, output, "diagnostics-timeout");
        await vm.DisconnectCommand.ExecuteAsync(null); await vm.ConnectCommand.ExecuteAsync(null);
        vm.Settings.Theme = vm.Settings.Themes.Single(x => x.Value == ThemeChoice.System);
        Check(store.Load().Theme == ThemeChoice.System, "System theme persists");
        using (var personalization = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
        {
            var expected = personalization?.GetValue("AppsUseLightTheme") is int value && value == 0 ? "Dark" : "Light";
            Check(services.GetRequiredService<ThemeService>().EffectiveTheme == expected, "System theme resolves the current Windows preference");
        }
        await KeymapSmokeTest.RunAsync(window, services, output, Check);
        await PhysicalControlsSmoke.RunAsync(window,services,output,Check);
        vm.NavigationSelection = vm.Navigation[0]; window.Width = 1600;
        ((FrameworkElement)window.Content).LayoutTransform = new ScaleTransform(1.5, 1.5);
        await Capture(window, output, "home-scale150");
        ((FrameworkElement)window.Content).LayoutTransform = Transform.Identity;
        Check(store.Load().Language == LanguageChoice.English && store.Load().CustomProfileName == "VS Code", "Language and custom name persist");
        Check(vm.Profiles.Cards.Select(c => (int)c.Profile.HardwareProfileId).SequenceEqual(new[] { 0,1,2,3 }), "Four immutable hardware slots");
        File.WriteAllLines(Path.Combine(output, "smoke-results.txt"), checks.Select(x => "PASS " + x));
    }
    internal static IEnumerable<DependencyObject> Descendants(DependencyObject parent)
    {
        for (int i=0; i<VisualTreeHelper.GetChildrenCount(parent); i++)
        { var child=VisualTreeHelper.GetChild(parent,i); yield return child; foreach(var d in Descendants(child)) yield return d; }
    }
    private static void ValidateVisibleText(Window window)
    {
        foreach(var block in Descendants(window).OfType<TextBlock>().Where(x=>x.IsVisible))
            if(block.Text.Contains("AhaKey.Studio.ViewModels") || block.Text.StartsWith('['))
                throw new InvalidOperationException("Unresolved UI content: " + block.Text);
    }
    internal static async Task Settle(Window window)
    { await window.Dispatcher.InvokeAsync(() => window.UpdateLayout(), DispatcherPriority.ApplicationIdle); await Task.Delay(80); }
    internal static async Task Capture(Window window, string output, string name)
    {
        await Settle(window);
        // A localization/theme switch can leave native text drawing clips cached during off-screen rendering.
        // Force a complete layout pass before recording evidence at the new viewport.
        foreach(var element in Descendants(window).OfType<UIElement>()) { element.InvalidateMeasure(); element.InvalidateArrange(); element.InvalidateVisual(); }
        window.InvalidateMeasure(); window.UpdateLayout();
        await window.Dispatcher.InvokeAsync(()=>window.UpdateLayout(),DispatcherPriority.ContextIdle);
        ValidateVisibleText(window);
        var surface = (FrameworkElement)window.Content;
        var bounds = surface.LayoutTransform.TransformBounds(new Rect(0, 0, surface.ActualWidth, surface.ActualHeight));
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(bounds.Width), (int)Math.Ceiling(bounds.Height), 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(surface);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var file = File.Create(Path.Combine(output, name + ".png")); encoder.Save(file);
    }
}

using System.IO;
using System.Windows;
using AhaKey.Studio.ViewModels;
using Microsoft.Extensions.DependencyInjection;

namespace AhaKey.Studio.Services;
// Isolated, hardware-free reproduction of the user-reported WPF binding failure.
public static class Phase8Repro
{
    public static string? Output;
    public static string? Fixture;
    public static string Scenario = "asset";
    private static IEnumerable<System.Windows.DependencyObject> Descendants(System.Windows.DependencyObject p)
    {for(int i=0;i<System.Windows.Media.VisualTreeHelper.GetChildrenCount(p);i++){var c=System.Windows.Media.VisualTreeHelper.GetChild(p,i);yield return c;foreach(var d in Descendants(c))yield return d;}}
    public static async Task RunAsync(Window window, IServiceProvider services)
    {
        var vm = services.GetRequiredService<ShellViewModel>();
        vm.Profiles.Selected = vm.Profiles.Cards[2];
        vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==PageId.Display);
        vm.DisplayPlanner.ImportFile(Fixture??Path.Combine(AppContext.BaseDirectory,"DisplayFixtures","timing.gif"));
        await vm.DisplayPlanner.Preparation;
        vm.DisplayPlanner.ProjectName = "GIF regression fixture";
        await vm.DisplayPlanner.SaveProjectCommand.ExecuteAsync(null);
        vm.DisplayPlanner.SelectedProject=null;vm.DisplayPlanner.ProjectName="Second asset";await vm.DisplayPlanner.SaveProjectCommand.ExecuteAsync(null);
        await Task.Delay(500);
        if(Scenario=="manual"){await Task.Delay(600000);return;}
        var checks=new List<string>();
        var list=vm.DisplayPlanner.Library;
        for(int pass=0;pass<6;pass++)
        {
            foreach(var project in list){vm.DisplayPlanner.SelectedProject=null;vm.DisplayPlanner.SelectedProject=project;await vm.DisplayPlanner.Preparation;window.UpdateLayout();if(vm.DisplayPlanner.Preview is null)throw new InvalidOperationException("Missing library preview");}
            foreach(var profile in vm.Profiles.Cards){vm.Profiles.Selected=profile;await vm.DisplayPlanner.Preparation;vm.Keymap.SelectedKey=vm.Keymap.Keys[1];vm.Keymap.Session.SetShortcut(new(AhaKey.Core.ShortcutModifiers.LeftCtrl,"Enter"));vm.Keymap.Refresh();window.UpdateLayout();await Task.Delay(15);}
        }
        checks.Add("PASS 48 library selections and 24 profile transitions without recursion");
        vm.Profiles.Selected=vm.Profiles.Cards[2];vm.DisplayPlanner.SelectedProject=list[0];
        var cancelled=vm.DisplayPlanner.Preparation;vm.DisplayPlanner.SelectedProject=list[1];await Task.WhenAll(cancelled,vm.DisplayPlanner.Preparation);
        if(vm.DisplayPlanner.SelectedProject!=list[1]||vm.DisplayPlanner.Preview is null)throw new InvalidOperationException("Stale conversion published");
        checks.Add("PASS cancellation leaves last selection authoritative");
        var seen=new HashSet<int>();for(int sample=0;sample<15;sample++){seen.Add(vm.DisplayPlanner.SelectedFrame);await Task.Delay(97);}if(vm.DisplayPlanner.Frames.Count>1&&seen.Count<2)throw new InvalidOperationException("Preview did not advance");
        checks.Add("PASS animated RGB565 preview advances");
        if(vm.Firmware.HasPackage){await vm.Firmware.VerifyCommand.ExecuteAsync(null);if(vm.Firmware.Result?.Contains(vm.L["FirmwarePackageVerified"])!=true)throw new InvalidOperationException("Known package failed validation");checks.Add("PASS known local HEX hash and provenance verified");}
        else {if(vm.Firmware.VerifyCommand.CanExecute(null)||!vm.Firmware.Package.Contains(vm.L["FirmwarePackageNotIncluded"]))throw new InvalidOperationException("Missing package offered as available");checks.Add("PASS public distribution honestly reports missing firmware and disables package verification");}
        if(vm.Ble.DiagnosticExport.Length>14000||vm.Ble.DiagnosticExport.Contains(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)))throw new InvalidOperationException("Diagnostics size/privacy");checks.Add("PASS compact diagnostics exclude user path");
        File.WriteAllLines(Path.Combine(Output!,"checks.txt"),checks);

        window.UpdateLayout();
        var combos = Descendants(window).OfType<System.Windows.Controls.ComboBox>().ToArray();
        if (Scenario == "asset") {var box=combos.Single(x=>System.Windows.Automation.AutomationProperties.GetName(x)==vm.L["DisplayLibrary"]);box.SelectedItem=null;box.SelectedItem=vm.DisplayPlanner.Library[0];}
        else {var box=combos.First(x=>x.Items.Contains(vm.Profiles.Cards[1]));box.SelectedItem=vm.Profiles.Cards[1];}
        await Task.Delay(1000);
        var invalid=Path.Combine(Output!,"invalid.gif");File.WriteAllText(invalid,"This is not a GIF");
        vm.DisplayPlanner.ImportFile(invalid);await vm.DisplayPlanner.Preparation;
        if(vm.DisplayPlanner.ModernPlan is not null||vm.DisplayPlanner.Plan is not null||vm.DisplayPlanner.Preview is not null)throw new InvalidOperationException("Failed import retained a stale upload plan");
        checks.Add("PASS invalid import clears previous preview and upload plan");
        File.WriteAllLines(Path.Combine(Output!,"checks.txt"),checks);
        File.WriteAllText(Path.Combine(Output!,"result.txt"), "completed");
        Application.Current.Shutdown();
    }
}

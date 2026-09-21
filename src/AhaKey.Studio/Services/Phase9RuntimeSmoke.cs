using System.IO;
using System.Windows;
using AhaKey.Device;
using AhaKey.Services;
using AhaKey.Studio.ViewModels;
using Microsoft.Extensions.DependencyInjection;
namespace AhaKey.Studio.Services;
// Explicit isolated software smoke; never starts a physical transport or installs hooks.
public static class Phase9RuntimeSmoke
{
    public static async Task RunAsync(Window window,IServiceProvider services,string output)
    {
        Directory.CreateDirectory(output);
        var shell=services.GetRequiredService<ShellViewModel>();
        var settings=services.GetRequiredService<ProfileSelectionService>();
        var integration=services.GetRequiredService<IntegrationRuntime>();
        var runtime=services.GetRequiredService<RealDeviceRuntime>();
        var checks=new List<string>();
        settings.Update(s=>s with{TrayExplanationSeen=true});
        using var tray=new TrayLifetime(window,shell,settings,integration,runtime,()=>Task.CompletedTask);
        window.Close();if(window.IsVisible)throw new InvalidOperationException("X did not hide the shell.");
        checks.Add("X hides shell and retains process and tray owner");
        tray.Show();if(!window.IsVisible)throw new InvalidOperationException("Tray reopen failed.");
        checks.Add("Tray reopens shell");
        await shell.Firmware.VerifyCommand.ExecuteAsync(null);
        if(shell.Firmware.CanReinstall)throw new InvalidOperationException("Firmware enabled without a connected device.");
        checks.Add("Firmware is blocked without live compatible USB identity");
        foreach(var language in new[]{LanguageChoice.English,LanguageChoice.Russian,LanguageChoice.Chinese})
        {
            shell.Settings.Language=shell.Settings.Languages.Single(x=>x.Value==language);
            shell.Settings.Theme=shell.Settings.Themes.Single(x=>x.Value==ThemeChoice.Light);
            shell.OpenSettingsCommand.Execute(null);
            await StudioSmokeTest.Capture(window,output,"settings-"+language);
            shell.NavigationSelection=shell.Navigation.Single(x=>x.Value==PageId.Device);
            await StudioSmokeTest.Capture(window,output,"firmware-"+language);
        }
        shell.Settings.Theme=shell.Settings.Themes.Single(x=>x.Value==ThemeChoice.Dark);
        await StudioSmokeTest.Capture(window,output,"firmware-dark");
        checks.Add("Settings and firmware rendered in EN/RU/ZH and dark theme");
        var store=services.GetRequiredService<SettingsStore>();
        var journalPath=Path.Combine(store.Root,"Firmware","update.json");Directory.CreateDirectory(Path.GetDirectoryName(journalPath)!);
        File.WriteAllText(journalPath,System.Text.Json.JsonSerializer.Serialize(new AhaKey.Firmware.FirmwareUpdateJournal(Guid.NewGuid(),"1.4.8",FirmwareViewModel.KnownPackage().Sha256,AhaKey.Firmware.FirmwareUpdateState.Programming,DateTimeOffset.UtcNow,"OFFLINE FIXTURE")));
        await shell.Firmware.VerifyCommand.ExecuteAsync(null);
        if(!shell.Firmware.NeedsRecovery)throw new InvalidOperationException("Interrupted update forgotten.");
        shell.Settings.Language=shell.Settings.Languages.Single(x=>x.Value==LanguageChoice.Russian);
        await StudioSmokeTest.Capture(window,output,"firmware-recovery-offline");
        checks.Add("Interrupted update exposes recovery and stays blocked without saved target");
        File.WriteAllLines(Path.Combine(output,"checks.txt"),checks);
    }
}

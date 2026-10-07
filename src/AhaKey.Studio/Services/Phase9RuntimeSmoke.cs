using System.IO;
using System.Windows;
using AhaKey.Device;
using AhaKey.Core;
using AhaKey.Integrations;
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
        await services.GetRequiredService<FirmwareRuntime>().InspectAsync();
        await shell.Firmware.VerifyCommand.ExecuteAsync(null);
        if(!shell.Firmware.NeedsRecovery)throw new InvalidOperationException("Interrupted update forgotten.");
        shell.Settings.Language=shell.Settings.Languages.Single(x=>x.Value==LanguageChoice.Russian);
        await StudioSmokeTest.Capture(window,output,"firmware-recovery-offline");
        checks.Add("Interrupted update exposes recovery and stays blocked without saved target");
        await CheckReleaseFeaturesAsync(window,services,output,checks);
        File.WriteAllLines(Path.Combine(output,"checks.txt"),checks);
    }
    private static async Task CheckReleaseFeaturesAsync(Window window,IServiceProvider services,string output,List<string> checks)
    {
        void Check(bool value,string message){if(!value)throw new InvalidOperationException(message);checks.Add("OFFLINE REPLAY PASS "+message);}
        var shell=services.GetRequiredService<ShellViewModel>();var usb=services.GetRequiredService<UsbReplayFactory>();
        var preferences=services.GetRequiredService<ProfileSelectionService>();var controls=services.GetRequiredService<PhysicalControlRuntime>();
        var activation=services.GetRequiredService<ProfileActivationRuntime>();var integrations=services.GetRequiredService<IntegrationRuntime>();
        usb.Contract32=true;usb.ProductControls=true;
        await shell.Ble.ChooseUsbCommand.ExecuteAsync(null);await shell.Ble.ConnectCommand.ExecuteAsync(null);
        Check(shell.Manager.RealDevice?.WritesSupported==true,"X1 1.4.8 identity permits real typed execution path");
        shell.Profiles.Selected=shell.Profiles.Cards[2];var draft=shell.Manager.Tracker.Draft;
        activation.Enable(true);usb.ModeEvent!(1);
        Check(shell.Manager.RealDevice!.Observation.Status!.WorkMode==1&&preferences.Settings.SelectedProfile==HardwareProfileId.Codex&&ReferenceEquals(draft,shell.Manager.Tracker.Draft),"9B changes hardware profile and preserves editor draft");
        await activation.ActivateAsync(HardwareProfileId.Codex);
        Check(usb.Controls.Contains("AABB9202CCDD")&&activation.ErrorKey is null&&shell.Manager.RealDevice.Observation.Status!.WorkMode==2,"Selecting cached P2 after physical P1 sends 92 and confirms P2");
        await shell.Settings.ReadSleepCommand.ExecuteAsync(null);Check(shell.Settings.SleepMinutes==5,"Sleep read uses 95");
        shell.Settings.SleepMinutes=10;await shell.Settings.ApplySleepCommand.ExecuteAsync(null);
        Check(usb.Controls.Contains("AABB950A00CCDD")&&usb.Controls.Contains("AABB04CCDD")&&shell.Settings.SleepStatusKey=="SleepConfirmed","Sleep setter is little endian, saves 04 and reads confirmation");
        usb.TaskMode=1;usb.TaskSlots[1]=1;
        var preservedSlots=usb.TaskSlots.ToArray();int previewStart=usb.Controls.Count;
        controls.EnableFeedback(HardwareProfileId.Codex,"Codex",true);
        var preview=controls.PreviewAsync(12,"Offline manual lighting preview");
        await Task.Delay(150);
        Check(shell.Manager.Operations.Current?.Operation=="Lighting preview","Manual preview retains exclusive gate during visible effect");
        await controls.ApplyAggregateAsync(HardwareProfileId.Codex,"Codex",true);
        await preview;
        Check(usb.Controls.Skip(previewStart).SequenceEqual(new[]{"AABB9A01CCDD","AABB9800CCDD","AABB910CCCDD","AABB9100CCDD","AABB9801CCDD"}),"Preview reads mode, shows selected effect and restores multi mode without save or feedback overwrite");
        Check(usb.TaskMode==1 && usb.TaskSlots.SequenceEqual(preservedSlots),"Manual lighting preview preserves all task slots");
        usb.TaskMode=0;Array.Clear(usb.TaskSlots);
        Check(integrations.Manager.Server.Start(0),"Isolated integration listener uses an ephemeral local port");
        controls.EnableFeedback(HardwareProfileId.Codex,"Codex",true);
        await Task.Delay(1200); // Initialize the runtime's current-session generation before task ingress.
        await integrations.SetTasksEnabledAsync(true);Check(integrations.TasksEnabled,"Explicit multiple-task mode is acknowledged");
        for(int i=0;i<5;i++)integrations.Coordinator.Accept(new(AssistantId.Codex,IdeEvent.PreToolUse,"fixture"){TaskId="task-"+i,EventId="start-"+i});
        integrations.Coordinator.Accept(new(AssistantId.Codex,IdeEvent.PermissionRequest,"fixture"){TaskId="task-4",EventId="attention"});
        await Task.Delay(1600);
        Check(integrations.TasksStatusKey=="TasksOverflow"&&Enumerable.Range(0,4).Count(i=>usb.TaskSlots[i*3+1]!=0)==4&&Enumerable.Range(0,4).Any(i=>usb.TaskSlots[i*3+1]==2),"Four slots preserve independent tasks and prioritize attention on overflow");
        Check(await shell.Manager.Operations.WaitAsync(0,default),"Fixture acquires exclusive operation gate");
        int writes=usb.Controls.Count;await Task.Delay(1300);Check(usb.Controls.Count==writes,"Task maintenance yields to an exclusive operation");shell.Manager.Operations.Release();
        await Task.Delay(9000);
        Check(usb.Controls.Contains("AABB9A00CCDD"),"Ten-second heartbeat accepts seven-byte active mask response");
        shell.Manager.Operations.ShutdownRequested=true;
        await integrations.SetTasksEnabledAsync(false);
        shell.Manager.Operations.ShutdownRequested=false;
        Check(!integrations.TasksEnabled&&usb.TaskMode==0&&Enumerable.Range(0,4).All(i=>usb.TaskSlots[i*3+1]==0),"Disable/Exit cleanup releases owned slots and display mode under shutdown restriction");
        usb.TaskSlots[1]=1;int modes=usb.Controls.Count(x=>x.StartsWith("AABB98",StringComparison.Ordinal));await integrations.SetTasksEnabledAsync(true);
        Check(!integrations.TasksEnabled&&modes==usb.Controls.Count(x=>x.StartsWith("AABB98",StringComparison.Ordinal)),"Occupied slots are never taken over");usb.TaskSlots[1]=0;
        await integrations.Manager.Server.DisposeAsync();
        shell.Project.VoiceShortLong=true;shell.Project.VoiceLongAction=shell.Project.VoiceActions.Single(x=>x.Value==VoiceHostAction.LocalShortcut);shell.Project.VoiceLongShortcut="Ctrl+Enter";
        shell.OpenSettingsCommand.Execute(null);
        foreach(var language in new[]{LanguageChoice.English,LanguageChoice.Russian,LanguageChoice.Chinese})
        {
            shell.Settings.Language=shell.Settings.Languages.Single(x=>x.Value==language);
            await StudioSmokeTest.Capture(window,output,"release-settings-"+language);
            var scroll=StudioSmokeTest.Descendants(window).OfType<System.Windows.Controls.ScrollViewer>().First(x=>x.Content is System.Windows.Controls.Grid);
            scroll.ScrollToBottom();await StudioSmokeTest.Capture(window,output,"release-voice-"+language);scroll.ScrollToTop();
            Check(!StudioSmokeTest.Descendants(window).OfType<System.Windows.Controls.TextBlock>().Any(t=>t.Text.StartsWith("[",StringComparison.Ordinal)),language+" new settings have resolved resources");
            Check(StudioSmokeTest.Descendants(window).OfType<System.Windows.Controls.TextBlock>().Any(t=>t.Text==shell.Settings.SleepStatus),language+" sleep confirmation refreshes on language change");
        }
        checks.Add("OFFLINE REPLAY: no physical HID, BLE, key press, microphone, Windows login or MSI installation was exercised");
    }
}

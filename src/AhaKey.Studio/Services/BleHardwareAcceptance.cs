using System.IO;
using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Device.Ble;
using AhaKey.Services;
using AhaKey.Studio.ViewModels;
using Microsoft.Extensions.DependencyInjection;
namespace AhaKey.Studio.Services;
// Explicit CLI acceptance only. No startup auto-connection in ordinary application use.
public static class BleHardwareAcceptance
{
    public static async Task RunAsync(Window window,IServiceProvider services,string output,string selectedName)
    {
        Directory.CreateDirectory(output);
        var vm=services.GetRequiredService<ShellViewModel>();var real=services.GetRequiredService<RealAhaKeyDevice>();
        var snapshots=new List<BleDiagnostics>();var evidenceLock=new object();
        void CaptureEvidence(){lock(evidenceLock){var d=real.Diagnostics;if(snapshots.Count==0 || snapshots[^1].History.LastOrDefault()!=d.History.LastOrDefault())snapshots.Add(d);}}
        real.Changed+=CaptureEvidence;
        void CheckBridgeAbsent()
        {
            if(Process.GetProcessesByName("BLE_tcp_driver").Length>0)throw new InvalidOperationException("Legacy bridge is running.");
            var ip=IPGlobalProperties.GetIPGlobalProperties();
            if(ip.GetActiveTcpListeners().Any(x=>x.Port==9000)||ip.GetActiveTcpConnections().Any(x=>x.LocalEndPoint.Port==9000||x.RemoteEndPoint.Port==9000))throw new InvalidOperationException("Port 9000 is in use.");
        }
        try
        {
            CheckBridgeAbsent();
            vm.Settings.Language=vm.Settings.Languages.Single(x=>x.Value==LanguageChoice.English);
            vm.Settings.Backend=vm.Settings.Backends.Single(x=>x.Value==BackendChoice.Real);await vm.Settings.BackendChange;
            if(real.Diagnostics.SessionId is not null)throw new InvalidOperationException("Unexpected startup connection.");
            await vm.Ble.FindCommand.ExecuteAsync(null);
            var found=vm.Ble.Devices.Where(x=>x.Name==selectedName).ToArray();
            if(found.Length!=1)throw new InvalidOperationException("Explicit selection must match exactly one discovered device.");
            vm.Ble.Selected=found[0];await vm.Ble.ConnectCommand.ExecuteAsync(null);CheckBridgeAbsent();
            await File.WriteAllTextAsync(Path.Combine(output,"initial-redacted.json"),BleDiagnosticExport.Redacted(real.Diagnostics));
            if(!real.Diagnostics.IsLive)throw new InvalidOperationException("Hardware did not become ready: "+real.Diagnostics.ErrorKey);
            vm.Profiles.SelectCommand.Execute(vm.Profiles.Cards[2]);window.Width=1024;window.Height=900;
            vm.Ble.RedactIdentity=true;vm.Ble.Refresh();
            foreach(var language in new[]{LanguageChoice.English,LanguageChoice.Russian,LanguageChoice.Chinese})
            foreach(var theme in new[]{ThemeChoice.Light,ThemeChoice.Dark})
            {
                vm.Settings.Language=vm.Settings.Languages.Single(x=>x.Value==language);vm.Settings.Theme=vm.Settings.Themes.Single(x=>x.Value==theme);
                foreach(var page in new[]{PageId.Device,PageId.Diagnostics,PageId.Keymap})
                {
                    vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==page);
                    await StudioSmokeTest.Capture(window,output,$"real-{page}-{language}-{theme}-1024");
                    if(page==PageId.Diagnostics) {
                        var scroll=StudioSmokeTest.Descendants(window).OfType<ScrollViewer>().First(x=>x.ViewportHeight>500 && x.ScrollableHeight>500);
                        scroll.ScrollToVerticalOffset(720);await StudioSmokeTest.Capture(window,output,$"real-transport-{language}-{theme}-1024");
                        scroll.ScrollToBottom();await StudioSmokeTest.Capture(window,output,$"real-gatt-{language}-{theme}-1024");scroll.ScrollToTop();
                    }
                }
            }
            if(vm.CanWrite || vm.Keymap.CanTest || vm.Manager.Tracker.LastDeviceRead is not null || vm.Keymap.ProfileState==vm.L["Synced"])throw new InvalidOperationException("Real keymap provenance/write guard failed.");
            await vm.Ble.DisconnectCommand.ExecuteAsync(null);if(real.Diagnostics.IsLive||real.Diagnostics.Subscribed)throw new InvalidOperationException("Disconnect failed.");
            await vm.Ble.ReconnectCommand.ExecuteAsync(null);CheckBridgeAbsent();
            if(!real.Diagnostics.IsLive)throw new InvalidOperationException("Reconnect failed.");
            await File.WriteAllTextAsync(Path.Combine(output,"reconnected-redacted.json"),BleDiagnosticExport.Redacted(real.Diagnostics));
            await vm.Ble.DisconnectCommand.ExecuteAsync(null);
            vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==PageId.Device);await StudioSmokeTest.Capture(window,output,"real-disconnected-stale");
            // Save only the explicitly chosen identity into Studio's own settings, retaining all other preferences.
            var own=new ProfileSelectionService(new SettingsStore());own.Update(s=>s with{BleDeviceId=found[0].Id,BleDeviceName=found[0].Name,BleDeviceAddress=found[0].Address});
            await File.WriteAllTextAsync(Path.Combine(output,"acceptance.txt"),"PASS: in-process Windows BLE; bridge absent and no port 9000 before/during; explicit discover/select/connect; 00 then 9F; real keymap remains local; write disabled; disconnect; bounded reconnect; final disconnect; selected identity persisted.\n");
        }
        finally
        {
            await real.DisconnectAsync();real.Changed-=CaptureEvidence;
            BleDiagnostics[] captured;lock(evidenceLock)captured=snapshots.ToArray();
            var safe=captured.Select(d=>JsonSerializer.Deserialize<JsonElement>(BleDiagnosticExport.Redacted(d)));
            await File.WriteAllTextAsync(Path.Combine(output,"timeline-redacted.json"),JsonSerializer.Serialize(safe,new JsonSerializerOptions{WriteIndented=true}));
        }
    }
}

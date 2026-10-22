using System.Collections.Immutable;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using AhaKey.Core;
using AhaKey.Device.Ble;
using AhaKey.Services;
using AhaKey.Studio.ViewModels;
using Microsoft.Extensions.DependencyInjection;
namespace AhaKey.Studio.Services;

// Software-only replay of the Phase 3.1 captured 00/9F bytes. Never opens Windows BLE.
public sealed class LegacyDiagnosticsFactory : IWindowsGattSessionFactory
{
    public IWindowsGattSession Create(Guid id)=>new ReplaySession(id);
    private sealed class ReplaySession(Guid id) : IWindowsGattSession
    {
        public Guid Id=>id;
        public AdapterInfo Adapter=>new("OFFLINE EVIDENCE REPLAY","On");
        public bool NativeConnected {get;private set;}
        public GattResult? TeardownResult {get;private set;}
        public event Action<Guid,bool>? ConnectionChanged {add{} remove{}}
        private Action<BleNotification>? receiver;
        public Task<IReadOnlyList<BleDeviceInfo>> DiscoverAsync(TimeSpan duration,CancellationToken ct)=>Task.FromResult<IReadOnlyList<BleDeviceInfo>>([]);
        public Task AcquireAsync(string deviceId,CancellationToken ct){NativeConnected=true;return Task.CompletedTask;}
        public Task<ImmutableArray<GattServiceInfo>> DiscoverGattAsync(CancellationToken ct)
        {
            var c=GattContract.WindowsObserved;
            return Task.FromResult<ImmutableArray<GattServiceInfo>>([new(c.Service,[new(c.Data,GattFeatures.Write),new(c.Command,GattFeatures.Write),new(c.Notify,GattFeatures.Notify)],new(GattResultStatus.Success))]);
        }
        public Task<GattResult> SubscribeAsync(Guid service,Guid characteristic,Action<BleNotification> callback,CancellationToken ct)
        {receiver=callback;return Task.FromResult(new GattResult(GattResultStatus.Success));}
        public Task<GattResult> WriteCommandAsync(Guid service,Guid characteristic,ImmutableArray<byte> frame,CancellationToken ct)
        {
            var hex=Convert.ToHexString(frame.AsSpan()) switch {"AABB00CCDD"=>"AABB004A32010002000023CCDD","AABB9FCCDD"=>"AABB9F00CCDD",_=>throw new InvalidOperationException("Replay accepts only 00/9F.")};
            receiver?.Invoke(new(Id,DateTimeOffset.UtcNow,[..Convert.FromHexString(hex)]));
            return Task.FromResult(new GattResult(GattResultStatus.Success));
        }
        public ValueTask DisposeAsync(){NativeConnected=false;receiver=null;TeardownResult=new(GattResultStatus.Success);return ValueTask.CompletedTask;}
    }
}
public static class LegacyDiagnosticsSmoke
{
    public static async Task RunAsync(Window window,IServiceProvider services,string output)
    {
        Directory.CreateDirectory(output);var vm=services.GetRequiredService<ShellViewModel>();
        var checks=new List<string>();
        void Check(bool ok,string label){if(!ok)throw new InvalidOperationException(label);checks.Add(label);}
        vm.Settings.Backend=vm.Settings.Backends.Single(x=>x.Value==BackendChoice.Real);await vm.Settings.BackendChange;
        Check(vm.Ble.Summary.Single(x=>x.Label==vm.L["BleContract"]).Value==vm.L["BleUnknown"],"Before response contract is Unknown");
        vm.Ble.Selected=new("offline-replay","OFFLINE EVIDENCE REPLAY",null);
        vm.Profiles.SelectCommand.Execute(vm.Profiles.Cards[3]);
        vm.Manager.Edit(vm.Manager.Tracker.Draft with{GlobalBrightness=32});
        await vm.Ble.ConnectCommand.ExecuteAsync(null);Check(vm.Ble.Snapshot.IsLive,"00/9F replay connected through production transport");
        Check(vm.Manager.Tracker.Draft.GlobalBrightness==32,"Local draft survives real-backend connection");
        Check(vm.Profiles.Selected?.Profile.HardwareProfileId==HardwareProfileId.Custom,"Physical work-mode telemetry does not replace the selected local profile");
        Check(vm.Keymap.ProfileState!=vm.L["Synced"] && !vm.CanWrite,"Real Keymap never claims Synced and physical Write is disabled");
        Check(services.GetRequiredService<LocalDraftStore>().Load()?.GlobalBrightness==32,"Edited local draft persists independently from connection");
        vm.Profiles.SelectCommand.Execute(vm.Profiles.Cards[2]);
        window.Width=1024;window.Height=900;
        foreach(var language in new[]{LanguageChoice.English,LanguageChoice.Russian,LanguageChoice.Chinese})
        foreach(var theme in new[]{ThemeChoice.Light,ThemeChoice.Dark})
        {
            vm.Settings.Language=vm.Settings.Languages.Single(x=>x.Value==language);vm.Settings.Theme=vm.Settings.Themes.Single(x=>x.Value==theme);
            var summary=vm.Ble.Summary;
            Check(summary.Single(x=>x.Label==vm.L["BleContract"]).Value==vm.L["BleLegacyIncomplete"],$"{language}/{theme}: legacy incomplete");
            Check(summary.Single(x=>x.Label==vm.L["BleCapabilities"]).Value==vm.L["BleNotReported"],$"{language}/{theme}: capabilities absent");
            Check(summary.Single(x=>x.Label==vm.L["BleFirmware"]).Value=="1.0",$"{language}/{theme}: no invented patch");
            Check(!vm.CanWrite && !vm.Keymap.CanTest && vm.Manager.Tracker.LastDeviceRead is null,$"{language}/{theme}: read-only local draft");
            vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==PageId.Diagnostics);
            await StudioSmokeTest.Capture(window,output,$"diagnostics-{language}-{theme}");
            var scroll=StudioSmokeTest.Descendants(window).OfType<ScrollViewer>().First(x=>x.ViewportHeight>400);
            scroll.ScrollToVerticalOffset(320);await StudioSmokeTest.Capture(window,output,$"contract-{language}-{theme}");scroll.ScrollToTop();
        }
        window.Height=720;await StudioSmokeTest.Capture(window,output,"diagnostics-minimum");
        await vm.Ble.DisconnectCommand.ExecuteAsync(null);
        Check(!vm.Ble.Snapshot.IsLive && vm.Ble.Freshness.Contains(vm.L["BleStale"]),"Retained observations are stale after disconnect with transport provenance");
        Check(services.GetRequiredService<ProfileSelectionService>().Settings.BleDeviceId=="offline-replay","Disconnect retains selected device preference");
        await services.GetRequiredService<AhaKey.Device.RealDeviceRuntime>().StartAsync();
        Check(vm.Ble.Snapshot.IsLive,"Known-device startup reconnect uses the saved selection");
        await vm.Ble.ForgetCommand.ExecuteAsync(null);
        Check(vm.Ble.Selected is null && vm.Manager.RealDevice!.Selected is null && services.GetRequiredService<ProfileSelectionService>().Settings.BleDeviceId is null,"Forget disconnects and clears runtime and persisted identity");
        Check(vm.Manager.Tracker.Draft.GlobalBrightness==32,"Forget preserves local configuration");
        vm.Settings.DeveloperMode=true;await vm.Settings.BackendChange;
        vm.Settings.Backend=vm.Settings.Backends.Single(x=>x.Value==BackendChoice.Mock);await vm.Settings.BackendChange;
        Check(!vm.Manager.RealBackendSelected,"Developer mode exposes explicit Mock selection");
        await vm.Manager.ConnectAsync();await vm.Manager.WriteAndReadAsync();Check(vm.Manager.Tracker.State==SyncState.Synced,"Mock write/readback still works after backend switch");
        vm.Settings.DeveloperMode=false;await vm.Settings.BackendChange;
        Check(vm.Manager.RealBackendSelected,"Leaving Developer mode returns to Real without fallback");
        await StudioSmokeTest.Capture(window,output,"diagnostics-stale");
        File.WriteAllLines(Path.Combine(output,"checks.txt"),checks.Prepend("OFFLINE REPLAY; zero physical BLE operations"));
    }
}

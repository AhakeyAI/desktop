using System.Collections.Immutable;
using System.IO;
using System.Windows;
using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Device.Usb;
using AhaKey.Services;
using AhaKey.Studio.ViewModels;
using Microsoft.Extensions.DependencyInjection;
namespace AhaKey.Studio.Services;

// Hardware-free replay only; not evidence that any physical USB device supports these responses.
public sealed class UsbReplayFactory : IWindowsHidSessionFactory
{
    public IReadOnlyList<HidCandidate> Candidates {get;set;}=[new("offline-replay","offline-instance",0x413C,0x2107,1,null,0xFF00,1,65,65,0,[0],[0],null,null)];
    public bool ProductControls {get;set;}
    public bool FailNextControl {get;set;}
    public bool Contract32 {get;set;}
    public List<string> Controls {get;}=[];
    public int DisplayReports {get;set;}
    public int OutputCount {get;private set;}
    public Task<IReadOnlyList<HidCandidate>> EnumerateAsync(CancellationToken ct)=>Task.FromResult(Candidates);
    public IWindowsHidSession Create(Guid id)=>new Replay(id,this);
    private sealed class Replay(Guid id,UsbReplayFactory owner) : IWindowsHidSession
    {
        public Guid Id=>id;
        public bool ReaderRunning {get;private set;}
        private Action<HidInput>? receive;
        public Task OpenAsync(HidCandidate candidate,Action<HidInput> input,Action<Guid,Exception> failed,CancellationToken ct){ReaderRunning=true;receive=input;return Task.CompletedTask;}
        public Task<HidWriteResult> WriteAsync(ImmutableArray<byte> report,CancellationToken ct)
        {
            if(!AhaKey.Protocol.UsbReportCodec.IsAllowedReport(report.AsSpan()))throw new InvalidOperationException("Replay allowlist.");
            owner.OutputCount++;var bytes=new byte[65];Convert.FromHexString(owner.Contract32?(report[5]==0?"AABB004B3201040200002304CCDD":"AABB9F000302010401FF0700000801CCDD"):(report[5]==0?"AABB004B32010002000023CCDD":"AABB9F00CCDD")).CopyTo(bytes,1);
            receive?.Invoke(new(Id,DateTimeOffset.UtcNow,bytes.ToImmutableArray()));return Task.FromResult(new HidWriteResult(true,65,0));
        }
        private int remaining;
        private void Emit(string frame){var r=new byte[65];Convert.FromHexString(frame).CopyTo(r,1);receive!(new(Id,DateTimeOffset.UtcNow,[..r]));}
        public Task<HidWriteResult> WriteControlAsync(ApprovedControl control,CancellationToken ct)
        {
            if(!owner.ProductControls)throw new NotSupportedException();
            control.Consume(Id,control.Command.Frame.AsSpan());owner.Controls.Add(Convert.ToHexString(control.Command.Frame.AsSpan()));
            var status=owner.FailNextControl?1:0;owner.FailNextControl=false;
            Emit($"AABB{control.Command.Frame[2]:X2}{status:X2}CCDD");return Task.FromResult(new HidWriteResult(true,65,0));
        }
        public Task<HidWriteResult> WriteDisplayAsync(ApprovedDisplayReport permit,CancellationToken ct)
        {
            if(!owner.ProductControls)throw new NotSupportedException();permit.Consume(Id);var r=permit.Report;owner.DisplayReports++;
            if(r[1]==0xA1){byte op=r[5];if(op==0x80)remaining=r[7]|r[8]<<8;Emit(op==0x83?"AABB8300020900010064002401CCDD":$"AABB{op:X2}00CCDD");}
            else{remaining-=r[2];if(remaining==0)Emit("AABB8100CCDD");}
            return Task.FromResult(new HidWriteResult(true,65,0));
        }
        public void Cancel() { }
        public ValueTask DisposeAsync(){ReaderRunning=false;return ValueTask.CompletedTask;}
    }
}
public static class UsbDiagnosticsSmoke
{
    public static async Task RunAsync(Window window,IServiceProvider services,string output)
    {
        Directory.CreateDirectory(output);var checks=new List<string>{"OFFLINE USB/BLE REPLAY — zero physical operations"};
        void Check(bool value,string name){if(!value)throw new InvalidOperationException(name);checks.Add(name);}
        var vm=services.GetRequiredService<ShellViewModel>();var usb=services.GetRequiredService<UsbReplayFactory>();
        var runtime=services.GetRequiredService<RealDeviceRuntime>();var real=vm.Manager.RealDevice!;
        vm.Ble.Selected=new("replay-ble","OFFLINE BLE REPLAY",null);await runtime.StartAsync();Check(real.Diagnostics.IsLive,"BLE replay works before handoff");
        var local=vm.Manager.Tracker.Draft;var valid=usb.Candidates;
        await vm.Ble.ChooseUsbCommand.ExecuteAsync(null);
        Check(vm.Ble.IsUsb && !real.Diagnostics.IsLive,"Switch to USB closes BLE before explicit connect");
        Check(usb.OutputCount==0 && !vm.Ble.Fresh,"Enumeration emits no report and never imports BLE battery");
        vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==PageId.Device);window.Width=1024;window.Height=920;
        await StudioSmokeTest.Capture(window,output,"usb-identified-offline");
        usb.Candidates=[];await vm.Ble.FindCommand.ExecuteAsync(null);Check(!vm.Ble.CanConnect,"No USB candidate disables Connect");
        usb.Candidates=[valid[0],valid[0] with{Path="second"}];await vm.Ble.FindCommand.ExecuteAsync(null);Check(!vm.Ble.CanConnect && vm.Ble.CandidateMessage==vm.L["UsbAmbiguous"],"Ambiguous USB disables Connect and explains why");
        await StudioSmokeTest.Capture(window,output,"usb-ambiguous-offline");
        usb.Candidates=valid;await vm.Ble.FindCommand.ExecuteAsync(null);await vm.Ble.ConnectCommand.ExecuteAsync(null);
        Check(real.Observation.IsLive && usb.OutputCount==2,"Explicit USB connect sends only one 00/9F pair");
        Check(ReferenceEquals(local,vm.Manager.Tracker.Draft) && !vm.CanWrite && !vm.Keymap.CanTest && vm.Manager.Tracker.LastDeviceRead is null,"USB keeps local draft and disables physical writes and Test");
        Check(vm.Ble.Freshness.StartsWith("USB") && vm.Ble.Summary.Any(x=>x.Value=="1.0"),"USB telemetry retains transport/timestamp and firmware 1.0");
        foreach(var language in new[]{LanguageChoice.English,LanguageChoice.Russian,LanguageChoice.Chinese})
        foreach(var theme in new[]{ThemeChoice.Light,ThemeChoice.Dark})
        {
            vm.Settings.Language=vm.Settings.Languages.Single(x=>x.Value==language);vm.Settings.Theme=vm.Settings.Themes.Single(x=>x.Value==theme);
            Check(vm.Ble.Summary.Single(x=>x.Label==vm.L["BleCapabilities"]).Value==vm.L["BleNotReported"],$"{language}/{theme}: missing capabilities stay missing");
            Check(!vm.Ble.Summary.Any(x=>x.Value.Contains("OLED")) && vm.L["Display"].IndexOf("OLED",StringComparison.OrdinalIgnoreCase)<0,$"{language}/{theme}: Display terminology");
            vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==PageId.Device);await StudioSmokeTest.Capture(window,output,$"usb-device-{language}-{theme}-1024-offline");
            vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==PageId.Diagnostics);await StudioSmokeTest.Capture(window,output,$"usb-diagnostics-{language}-{theme}-1024-offline");
        }
        // Isolated host fixture only: acceptance visuals never promote a physical device.
        var settings=services.GetRequiredService<SettingsStore>();
        var acceptancePath=Path.Combine(settings.Root,"physical-controls-acceptance.json");
        File.WriteAllText(acceptancePath,System.Text.Json.JsonSerializer.Serialize(new ControlAcceptance(PhysicalControlRuntime.DeviceHash(real)!,real.Identity.Firmware,true,[0,1],"OFFLINE REPLAY FIXTURE")));
        vm.Profiles.Selected=vm.Profiles.Cards[2];vm.Keymap.SelectedKey=vm.Keymap.Keys[1];
        AhaKey.Core.ShortcutGesture.TryParse("Ctrl+Enter",out var shortcut);vm.Keymap.Session.SetShortcut(shortcut!);vm.Keymap.DeviceLabel="Send";
        vm.Keymap.Refresh();vm.Controls.Refresh();
        Check(vm.Keymap.CanWritePhysical && vm.Controls.CanPreview,"Offline accepted capability fixture enables typed controls");
        var before=usb.OutputCount;
        foreach(var language in new[]{LanguageChoice.English,LanguageChoice.Russian,LanguageChoice.Chinese})
        foreach(var theme in new[]{ThemeChoice.Light,ThemeChoice.Dark})
        {
            vm.Settings.Language=vm.Settings.Languages.Single(x=>x.Value==language);vm.Settings.Theme=vm.Settings.Themes.Single(x=>x.Value==theme);
            foreach(var page in new[]{PageId.Keymap,PageId.Lighting})
            {
                vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==page);
                var scroll=StudioSmokeTest.Descendants(window).OfType<System.Windows.Controls.ScrollViewer>().First(x=>x.Content is System.Windows.Controls.Grid);scroll.ScrollToTop();
                await StudioSmokeTest.Capture(window,output,$"phase4b-accepted-{page}-{language}-{theme}-1024-offline");
                if(page==PageId.Lighting){scroll.ScrollToBottom();await StudioSmokeTest.Capture(window,output,$"phase4b-feedback-{language}-{theme}-1024-offline");scroll.ScrollToTop();}
            }
        }
        // Phase 5 capability/UI replay. This file lives under this smoke run's isolated settings only.
        var proof=new StaticDisplayAcceptance(Guid.NewGuid(),2,9,new string('A',64),true,true,true);
        var capability=new ControlAcceptance(PhysicalControlRuntime.DeviceHash(real)!,real.Identity.Firmware,true,[0,1],"OFFLINE PHASE 5 REPLAY"){StaticDisplay=proof};
        File.WriteAllText(acceptancePath,System.Text.Json.JsonSerializer.Serialize(capability));
        var fixtures=Path.Combine(AppContext.BaseDirectory,"DisplayFixtures");
        vm.DisplayPlanner.LoadFixture(Path.Combine(fixtures,"timing.gif"));Check(!vm.DisplayPlanner.CanUpload,"GIF cannot enter physical static writer");
        vm.DisplayPlanner.LoadFixture(Path.Combine(fixtures,"native-canvas.png"));Check(vm.DisplayPlanner.CanUpload,"Accepted USB static profile 2 / Default enables confirmation entry");
        File.WriteAllText(acceptancePath,System.Text.Json.JsonSerializer.Serialize(capability with{StaticDisplay=proof with{VisuallyObserved=false}}));
        Check(!vm.DisplayPlanner.CanUpload,"Metadata-only acceptance cannot enable physical upload");
        File.WriteAllText(acceptancePath,System.Text.Json.JsonSerializer.Serialize(capability));
        vm.Profiles.Selected=vm.Profiles.Cards[1];Check(!vm.DisplayPlanner.CanUpload,"Another profile cannot enter static writer");vm.Profiles.Selected=vm.Profiles.Cards[2];
        vm.DisplayPlanner.Asset=vm.DisplayPlanner.Assets.Single(x=>x.Value==DisplayState.Working);Check(!vm.DisplayPlanner.CanUpload,"Another display state cannot enter static writer");
        vm.DisplayPlanner.Asset=vm.DisplayPlanner.Assets.Single(x=>x.Value==DisplayState.Default);
        vm.Keymap.SelectedKey=vm.Keymap.Keys[0];Check(!vm.Keymap.Editable && !vm.Keymap.CanWritePhysical,"K1 remains locked after unobserved F19");
        foreach(var language in new[]{LanguageChoice.English,LanguageChoice.Russian,LanguageChoice.Chinese})
        foreach(var theme in new[]{ThemeChoice.Light,ThemeChoice.Dark})
        {
            vm.Settings.Language=vm.Settings.Languages.Single(x=>x.Value==language);vm.Settings.Theme=vm.Settings.Themes.Single(x=>x.Value==theme);
            var scroll=StudioSmokeTest.Descendants(window).OfType<System.Windows.Controls.ScrollViewer>().First(x=>x.Content is System.Windows.Controls.Grid);
            vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==PageId.Keymap);scroll.ScrollToTop();await StudioSmokeTest.Capture(window,output,$"phase5-k1-locked-{language}-{theme}-1024-offline");
            vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==PageId.Lighting);
            vm.Controls.FeedbackEnabled=false;scroll.ScrollToTop();await StudioSmokeTest.Capture(window,output,$"phase5-lighting-{language}-{theme}-1024-offline");
            scroll.ScrollToBottom();await StudioSmokeTest.Capture(window,output,$"phase5-feedback-off-{language}-{theme}-1024-offline");
            vm.Controls.FeedbackEnabled=true;await StudioSmokeTest.Capture(window,output,$"phase5-feedback-on-{language}-{theme}-1024-offline");vm.Controls.FeedbackEnabled=false;
            vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==PageId.Display);scroll.ScrollToTop();await StudioSmokeTest.Capture(window,output,$"phase5-static-{language}-{theme}-1024-offline");
            var review=new Views.DisplayOverwriteWindow(vm.DisplayPlanner.StaticPlan!,vm.L){Owner=window};review.Show();await StudioSmokeTest.Capture(review,output,$"phase5-overwrite-{language}-{theme}-offline");review.Close();
        }
        Check(usb.OutputCount==before,"Inspecting accepted controls and closing overwrite confirmation sends zero commands");
        vm.Controls.FeedbackEnabled=true;

        await vm.Ble.DisconnectCommand.ExecuteAsync(null);Check(!vm.Ble.Fresh && !real.Usb!.Diagnostics.ReaderRunning,"Disconnect stops reader and marks USB observations stale");
        await vm.Ble.ReconnectCommand.ExecuteAsync(null);Check(vm.Controls.FeedbackEnabled,"Reconnect preserves explicit product feedback preference");Check(usb.OutputCount==4,"Explicit USB reconnect performs exactly one query pair");
        var controls=services.GetRequiredService<PhysicalControlRuntime>();
        vm.Settings.Language=vm.Settings.Languages.Single(x=>x.Value==LanguageChoice.English);vm.Settings.Theme=vm.Settings.Themes.Single(x=>x.Value==ThemeChoice.Light);
        vm.Controls.FeedbackEnabled=true;vm.Controls.PreviewAccepted();
        await controls.HandleAsync(HardwareProfileId.Codex,"Codex",IdeEventState.PreToolUse,"CodexPreToolUse");
        Check(vm.Controls.FeedbackEnabled && !controls.FeedbackOperational(HardwareProfileId.Codex,"Codex") && vm.Controls.Message==vm.L["PhysicalFeedbackStopped"],"Feedback failure pauses output and preserves the explicit preference");
        vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==PageId.Lighting);
        var reviewScroll=StudioSmokeTest.Descendants(window).OfType<System.Windows.Controls.ScrollViewer>().First(x=>x.Content is System.Windows.Controls.Grid);reviewScroll.ScrollToBottom();
        await StudioSmokeTest.Capture(window,output,"phase4b-feedback-failure-after-preview-offline");
        await vm.Ble.ReconnectCommand.ExecuteAsync(null);Check(usb.OutputCount==6,"Failure fixture reconnect uses only 00/9F; no control retry");
        vm.Controls.FeedbackEnabled=true;Check(vm.Controls.FeedbackEnabled && vm.Controls.Message is null,"Explicit re-enable clears stale failure and preview status");
        await StudioSmokeTest.Capture(window,output,"phase4b-feedback-reenabled-offline");vm.Controls.FeedbackEnabled=false;
        vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==PageId.Device);reviewScroll.ScrollToTop();await StudioSmokeTest.Capture(window,output,"phase4b-device-qualified-write-scope-offline");
        reviewScroll.ScrollToBottom();await StudioSmokeTest.Capture(window,output,"phase4b-device-qualified-guidance-offline");
        File.Delete(acceptancePath);
        await vm.Ble.ChooseBluetoothCommand.ExecuteAsync(null);Check(!real.Usb!.Diagnostics.ReaderRunning && !vm.Ble.IsUsb,"USB to Bluetooth releases USB ownership");
        await vm.Ble.ConnectCommand.ExecuteAsync(null);Check(real.Diagnostics.IsLive,"BLE remains usable after USB");await runtime.DisconnectAsync();
        vm.Settings.DeveloperMode=true;await vm.Settings.BackendChange;vm.Settings.Backend=vm.Settings.Backends.Single(x=>x.Value==BackendChoice.Mock);await vm.Settings.BackendChange;
        await vm.Manager.ConnectAsync();await vm.Manager.WriteAndReadAsync();Check(vm.Manager.Tracker.State==SyncState.Synced,"Developer Mock still writes/readbacks locally after both real transports");
        File.WriteAllLines(Path.Combine(output,"checks.txt"),checks);
    }
}

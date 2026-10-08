using System.IO;
using System.Text.Json;
using System.Windows;
using AhaKey.Core;
using AhaKey.Integrations;
using AhaKey.Device;
using AhaKey.Protocol;
using AhaKey.Services;
using AhaKey.Studio.ViewModels;
using Microsoft.Extensions.DependencyInjection;

namespace AhaKey.Studio.Services;
// Only registered for an isolated, hardware-free replay; never replaces normal confirmations.
public sealed class ProductReplayDialogs:ProductDialogs
{
    public bool Approve {get;set;}
    public int KeyReviews {get;private set;}
    public int DisplayReviews {get;private set;}
    public override bool ConfirmKey(string preview,LocalizationService l){KeyReviews++;return Approve;}
    public override bool ConfirmDisplay(StaticDisplayPlan plan,LocalizationService l){DisplayReviews++;return Approve;}
}
public static class ProductSmoke
{
    public static async Task RunAsync(Window window,IServiceProvider services,string output)
    {
        Directory.CreateDirectory(output);var checks=new List<string>{"OFFLINE PRODUCT REPLAY; no physical device and no host configuration changes"};
        void Check(bool ok,string name){checks.Add((ok?"PASS ":"FAIL ")+name);File.WriteAllLines(Path.Combine(output,"checks.txt"),checks);if(!ok)throw new InvalidOperationException(name);}
        var vm=services.GetRequiredService<ShellViewModel>();var factory=services.GetRequiredService<UsbReplayFactory>();factory.ProductControls=true;
        var store=services.GetRequiredService<SettingsStore>();var preferences=services.GetRequiredService<ProfileSelectionService>();
        var dialogs=(ProductReplayDialogs)services.GetRequiredService<ProductDialogs>();
        Check(!vm.Settings.DeveloperMode && vm.Manager.RealBackendSelected,"Normal Real route, no Developer mode");
        vm.Profiles.Selected=vm.Profiles.Cards[2];await vm.Ble.ChooseUsbCommand.ExecuteAsync(null);await vm.Ble.ConnectCommand.ExecuteAsync(null);
        var real=vm.Manager.RealDevice!;
        var proof=new ControlAcceptance(PhysicalControlRuntime.DeviceHash(real)!,"1.0",true,[0,1],"OFFLINE FIXTURE")
        {StaticDisplay=new(Guid.NewGuid(),2,9,new string('A',64),true,true,true),ProfileSwitch=new(Guid.NewGuid(),true,true,true,true,true)};
        File.WriteAllText(Path.Combine(store.Root,"physical-controls-acceptance.json"),JsonSerializer.Serialize(proof));
        vm.Keymap.SelectedKey=vm.Keymap.Keys[1];vm.Keymap.ManualKey="Enter";vm.Keymap.SetManualModifier(ShortcutModifiers.LeftCtrl,true);vm.Keymap.DeviceLabel="Send";vm.Keymap.LocalName="Accept custom";
        Check(vm.Keymap.CanWritePhysical,"Accepted USB K2 Apply enabled in normal Real mode");
        await vm.Keymap.PhysicalWriteCommand.ExecuteAsync(null);Check(dialogs.KeyReviews==1 && factory.Controls.Count==0,"Cancel normal Apply sends no command");
        dialogs.Approve=true;
        for(int key=1;key<=3;key++)
        {
            vm.Keymap.SelectedKey=vm.Keymap.Keys[key];vm.Keymap.ManualKey=key==1?"Enter":key==2?"Escape":"Backspace";vm.Keymap.DeviceLabel=key==1?"Send":key==2?"Reject":"Back";
            await vm.Keymap.PhysicalWriteCommand.ExecuteAsync(null);
            Check(vm.Keymap.PhysicalState==vm.L["PhysicalWriteAccepted"],$"Normal K{key+1} Apply reports written, not readback or Synced");
        }
        Check(factory.Controls.Count==9 && factory.Controls.Count(x=>x=="AABB04CCDD")==3,"Minimal selected-key plans only, each shortcut/label/save once");
        Check(vm.SummaryKeys==vm.L["PhysicalWriteAccepted"],"Profile summary reflects all three local write receipts");
        vm.Keymap.SelectedKey=vm.Keymap.Keys[0];Check(!vm.Keymap.CanWritePhysical,"K1 unavailable in normal route");vm.Keymap.SelectedKey=vm.Keymap.Keys[1];
        vm.DisplayPlanner.ImportFile(Path.Combine(AppContext.BaseDirectory,"DisplayFixtures","native-canvas.png"));await vm.DisplayPlanner.Preparation;
        dialogs.Approve=false;await vm.DisplayPlanner.UploadCommand.ExecuteAsync(null);Check(dialogs.DisplayReviews==1 && factory.DisplayReports==0,"Cancel overwrite sends zero reports");
        dialogs.Approve=true;await vm.DisplayPlanner.UploadCommand.ExecuteAsync(null);Check(dialogs.DisplayReviews==2 && factory.DisplayReports==436,"Normal Display upload uses reviewed one-frame transaction");
        vm.Controls.FeedbackEnabled=true;vm.Integrations.AutoStart=true;
        var controls=services.GetRequiredService<PhysicalControlRuntime>();int beforeFeedback=factory.Controls.Count;
        await controls.HandleAsync(HardwareProfileId.Codex,"Codex",IdeEventState.PreToolUse,"CodexPreToolUse");
        await controls.StopFeedbackAsync();
        Check(factory.Controls.Skip(beforeFeedback).SequenceEqual(new[]{"AABB9101CCDD","AABB9100CCDD"}) && vm.Controls.FeedbackEnabled,"Stopping service neutralizes active feedback without erasing opt-in");
        var restarted=new ProfileSelectionService(new SettingsStore(store.Root));
        Check(restarted.Settings.SelectedProfile==HardwareProfileId.Codex && restarted.Settings.IntegrationAutoStart && restarted.Settings.PhysicalFeedback.Contains("2:Codex"),"Restart retains selection, auto-start and feedback opt-in");
        Check(restarted.LocalKeyName(HardwareProfileId.Codex,PhysicalKey.K2)=="Accept custom" && File.Exists(restarted.Settings.DisplaySources["2:0"].CachedPath),"Restart retains local names and cached Display source");
        var restartedHistory=new ProductWriteHistory(store);Check(restartedHistory.Find(proof.DeviceHash,"1.0","Key:2:1",ProductWriteHistory.KeyHash("Ctrl+Enter","Send")) is {BehaviorVerified:false},"Receipt survives restart without inventing behavior verification");
        vm.Profiles.Selected=vm.Profiles.Cards[1];Check(!vm.DisplayPlanner.UploadCommand.CanExecute(null),"Unsupported profile has no upload action");vm.Profiles.Selected=vm.Profiles.Cards[2];
        await vm.DisplayPlanner.Preparation;Check(vm.DisplayPlanner.Preview is not null,"Profile return restores imported preview");
        int reports=factory.DisplayReports;await vm.Ble.ChooseBluetoothCommand.ExecuteAsync(null);
        Check(vm.SummaryKeys==vm.L["ProductWrittenUsb"] && vm.Keymap.PhysicalState==vm.L["ProductWrittenUsb"] && !vm.Profiles.Cards[2].IsDirty,"Unchanged draft retains explicitly USB-labelled write history without claiming BLE readback");
        vm.Keymap.DeviceLabel="Changed";Check(vm.SummaryKeys==vm.L["PhysicalLocalOnly"] && vm.Profiles.Cards[2].IsDirty,"Actual draft changes remain marked local changes");vm.Keymap.DeviceLabel="Send";
        vm.Page=PageId.Keymap;vm.ActivateHardwareProfile=true;await vm.Activation.ActivateAsync(HardwareProfileId.Codex);
        Check(vm.HasError && vm.ErrorText!.Contains(vm.L["ProductProfileUnavailable"]) && vm.ErrorText.Contains(vm.HardwareProfile),"Profile activation failure stays visible outside Profiles with editing and physical status");
        window.Width=1024;window.Height=920;
        await StudioSmokeTest.Capture(window,output,"profile-switch-error-offline");
        vm.ActivateHardwareProfile=false;Check(!vm.HasError,"Disabling profile activation clears its failure");
        await vm.DisplayPlanner.UploadCommand.ExecuteAsync(null);Check(factory.DisplayReports==reports && vm.Page==PageId.Device && vm.DisplayPlanner.UploadResult==vm.L["ProductRequiresUsb"],"USB-required upload explains and opens Device with zero writes");
        vm.Ble.Selected=new("phase61-offline-ble","OFFLINE BLE REPLAY",null);await vm.Ble.ConnectCommand.ExecuteAsync(null);
        Check(real.Diagnostics.IsLive,"Product scenario starts with connected BLE");
        var candidates=factory.Candidates;factory.Candidates=[];vm.Keymap.DeviceLabel="USB test";int before=factory.Controls.Count;
        Check(vm.Keymap.CanWritePhysical,"BLE plus USB absent keeps Apply actionable");await vm.Keymap.PhysicalWriteCommand.ExecuteAsync(null);
        Check(factory.Controls.Count==before && real.Diagnostics.IsLive && vm.Keymap.Feedback==vm.L["ProductConnectUsbKeys"],"Missing USB requests cable and preserves BLE and local edits without writes");
        vm.Controls.FeedbackEnabled=false;
        Check(vm.Controls.NeedsUsb && !vm.Controls.CanEnableFeedback && vm.Controls.ConnectUsbCommand.CanExecute(null),"Unaccepted BLE lighting has direct Connect USB recovery");
        vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==PageId.Lighting);window.Width=1024;window.Height=920;await StudioSmokeTest.Capture(window,output,"lighting-connect-usb-offline");
        vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==PageId.Keymap);await StudioSmokeTest.Capture(window,output,"keys-connect-usb-offline");
        factory.Candidates=candidates;await vm.Keymap.PhysicalWriteCommand.ExecuteAsync(null);
        Check(factory.Controls.Count==before+3 && vm.Keymap.PhysicalState==vm.L["ProductWrittenUsb"] && real.Diagnostics.IsLive && !real.Usb!.Diagnostics.ReaderRunning,"BLE plus validated USB performs minimal write then restores BLE and preserves Written state");
        vm.Keymap.DeviceLabel="Failed draft";factory.FailNextControl=true;before=factory.Controls.Count;await vm.Keymap.PhysicalWriteCommand.ExecuteAsync(null);
        Check(vm.Keymap.DeviceLabel=="Failed draft" && vm.Keymap.PhysicalState==vm.L["PhysicalIndeterminate"] && vm.Keymap.Feedback==vm.L["PhysicalIndeterminate"] && factory.Controls.Count==before+1 && real.Diagnostics.IsLive,"Failed USB write retains edits, shows near-title recovery, does not save/retry and restores BLE");
        await StudioSmokeTest.Capture(window,output,"keys-write-failed-offline");
        vm.Keymap.DeviceLabel="Send";await vm.Keymap.PhysicalWriteCommand.ExecuteAsync(null);
        var bleProofPath=Path.Combine(store.Root,"ble-runtime-acceptance.json");
        File.WriteAllText(bleProofPath,JsonSerializer.Serialize(new BleRuntimeAcceptance(PhysicalControlRuntime.DeviceHash(real)!,real.Identity.Firmware,real.Observation.SessionId!.Value,true,true,"OFFLINE FIXTURE")));
        Check(controls.FeedbackAvailable && controls.Effects.SetEquals(new byte[]{0,1}) && !controls.KeyAvailable && !controls.StaticDisplayAvailable,"Accepted BLE proof promotes only runtime 01/00, never USB keys or Display");
        File.Delete(bleProofPath);
        await vm.Controls.ConnectUsbCommand.ExecuteAsync(null);
        Check(controls.FeedbackAvailable && !vm.Controls.NeedsUsb && real.Usb!.Diagnostics.IsLive && !real.Diagnostics.IsLive,"Lighting Connect USB acquires validated exclusive USB and enables toggle");vm.Controls.FeedbackEnabled=true;
        using(var export=JsonDocument.Parse(vm.Ble.DiagnosticExport))
        {
            var about=new Views.AboutDialog(vm.L);
            Check(ReferenceEquals(vm.Version,about.Version) && ReferenceEquals(vm.Version,vm.Ble.Version) && export.RootElement.GetProperty("Version").GetString()==about.Version.Version,"Footer About Diagnostics and diagnostic copy share assembly product-version source");
            about.Close();
        }
        await vm.Ble.ChooseUsbCommand.ExecuteAsync(null);await vm.Ble.ConnectCommand.ExecuteAsync(null);
        Check(vm.Controls.FeedbackEnabled,"Reconnect preserves preference");
        var project=services.GetRequiredService<LocalDeviceProjectStore>();
        vm.Keymap.SelectedKey=vm.Keymap.Keys[1];string originalShortcut=vm.Keymap.ManualKey!;vm.Keymap.SelectedPreset="Escape";vm.Keymap.ApplyPresetCommand.Execute(null);
        vm.Keymap.UndoCommand.Execute(null);Check(vm.Keymap.ManualKey==originalShortcut,"Key preset undo restores local intent with zero physical operation");
        var originalCustom=vm.Manager.Tracker.Draft.Profiles[HardwareProfileId.Custom];vm.Keymap.CopyProfile=vm.Profiles.Cards[3];vm.Keymap.CopyKeyToProfileCommand.Execute(null);
        Check(vm.Manager.Tracker.Draft.Profiles[HardwareProfileId.Custom].Keys[PhysicalKey.K2]==vm.Keymap.Session.Action,"Copy selected key to profile edits desired project only");
        vm.Keymap.UndoCommand.Execute(null);Check(vm.Manager.Tracker.Draft.Profiles[HardwareProfileId.Custom]==originalCustom,"Undo reverses cross-profile copy");
        vm.DisplayPlanner.ProjectName="Codex local artwork";await vm.DisplayPlanner.SaveProjectCommand.ExecuteAsync(null);
        Check(project.Current!.DisplayProjects.Length==1&&project.Current.EmbeddedAssets.Count==1,"Display library saves original asset and authoring metadata");
        vm.DisplayPlanner.SelectedProject=vm.DisplayPlanner.Library.Single();await vm.DisplayPlanner.Preparation;Check(vm.DisplayPlanner.Preview is {PixelWidth:160,PixelHeight:80},"Library restores exact 160x80 RGB565 preview");
        var portable=Path.Combine(output,"offline-project.ahakey.json");project.Export(portable);var imported=project.PreviewImport(portable);
        Check(imported.DisplayProjects.Length==1&&imported.DisplayAllocations.IsEmpty&&imported.LastSuccessfullySent.IsEmpty&&!imported.IsDeviceBackup,"Portable project retains asset and desired state, excludes physical claims");
        var restartedProject=new LocalDeviceProjectStore(new(store.Root)).LoadOrMigrate(DeviceConfiguration.Default,new());
        Check(restartedProject.Desired.EquivalentTo(vm.Manager.Tracker.Draft)&&restartedProject.DisplayProjects.Length==1,"Project restart restores local key and display authoring state");
        var importedNames=imported with{ProfileNames=imported.ProfileNames.SetItem(HardwareProfileId.Custom,"Imported workspace")};
        services.GetRequiredService<LocalProjectRuntime>().Import(importedNames);
        Check(vm.Profiles.Cards[3].Name=="Imported workspace"&&vm.Profiles.CustomName=="Imported workspace"&&vm.Keymap.LocalName=="Accept custom"&&vm.Controls.FeedbackEnabled,"Import refreshes local names and preserves explicit feedback opt-in without sending commands");
        var coordinator=new AssistantRuntimeCoordinator();int aggregationStart=factory.Controls.Count;
        async Task ApplyAggregate(){var state=coordinator.Aggregate();await controls.ApplyAggregateAsync(HardwareProfileId.Codex,"Codex",state.State>=AssistantProductState.Working);}
        coordinator.Accept(HookContract.Events["CodexSessionStart"] with{TaskId="task-A"});await ApplyAggregate();
        coordinator.Accept(HookContract.Events["CodexSessionStart"] with{TaskId="task-B"});await ApplyAggregate();
        coordinator.Accept(HookContract.Events["CodexStop"] with{TaskId="task-A"});await ApplyAggregate();
        Check(factory.Controls.Skip(aggregationStart).SequenceEqual(new[]{"AABB9101CCDD"}),"Completing task A leaves task B lighting active with no extra command");
        coordinator.Accept(HookContract.Events["CodexStop"] with{TaskId="task-B"});await ApplyAggregate();
        Check(factory.Controls.Skip(aggregationStart).SequenceEqual(new[]{"AABB9101CCDD","AABB9100CCDD"}),"Last task completion emits exactly one accepted neutral effect");
        Check(vm.Ble.Summary.Any(x=>x.Label==vm.L["FirmwareExactBuild"]&&x.Value==vm.L["BleUnknown"]),"Reported legacy 1.0 does not invent exact firmware build");
        window.Width=1024;window.Height=920;
        foreach(var language in new[]{LanguageChoice.English,LanguageChoice.Russian,LanguageChoice.Chinese})
        foreach(var theme in new[]{ThemeChoice.Light,ThemeChoice.Dark})
        {
            vm.Settings.Language=vm.Settings.Languages.Single(x=>x.Value==language);vm.Settings.Theme=vm.Settings.Themes.Single(x=>x.Value==theme);
            foreach(var page in new[]{PageId.Home,PageId.Keymap,PageId.Display,PageId.Lighting,PageId.Device,PageId.Settings})
            {
                if(page==PageId.Settings)vm.OpenSettingsCommand.Execute(null);else vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==page);
                StudioSmokeTest.Descendants(window).OfType<System.Windows.Controls.ScrollViewer>().First(x=>x.Content is System.Windows.Controls.Grid).ScrollToTop();
                await StudioSmokeTest.Capture(window,output,$"{page}-{language}-{theme}-1024-offline");
            }
            var review=new Views.DisplayOverwriteWindow(vm.DisplayPlanner.StaticPlan!,vm.L){Owner=window};review.Show();await StudioSmokeTest.Capture(review,output,$"overwrite-{language}-{theme}-offline");review.Close();
            var about=new Views.AboutDialog(vm.L){Owner=window};about.Show();await StudioSmokeTest.Capture(about,output,$"about-{language}-{theme}-offline");about.Close();
        }
        window.Height=720;vm.Settings.Language=vm.Settings.Languages.Single(x=>x.Value==LanguageChoice.Russian);
        foreach(var page in new[]{PageId.Keymap,PageId.Display,PageId.Settings}){if(page==PageId.Settings)vm.OpenSettingsCommand.Execute(null);else vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==page);foreach(var scroll in StudioSmokeTest.Descendants(window).OfType<System.Windows.Controls.ScrollViewer>())scroll.ScrollToTop();await StudioSmokeTest.Capture(window,output,$"{page}-Russian-Dark-1024x720-offline");}
        Check(!vm.Settings.DeveloperMode && vm.Manager.Tracker.LastDeviceRead is null,"Whole workflow stays normal UI and never claims configuration readback");
        factory.Contract32=true;await vm.Ble.ReadCommand.ExecuteAsync(null);
        Check(real.FirmwareIdentity is {Dialect:FirmwareDialect.WindowsContract32,ReportedPatch:8,KnownBuildHash:null},"Source-derived 3.2 replay identifies declared 1.4.8 without inventing build");
        Check(controls.KeyAvailable&&controls.FeedbackAvailable&&controls.Features.CanUploadDisplay(HardwareProfileId.Codex,DisplayState.Default,1).Available,"Live Windows 3.2 capabilities enable keys, lighting and allocated Display without legacy receipts");
        Check(vm.Keymap.PhysicalState!=vm.L["ProductWrittenUsb"]&&vm.Keymap.PhysicalState!=vm.L["PhysicalWriteAccepted"],"Old 1.0 write history does not claim current 1.4.8 configuration");
        await vm.Ble.DisconnectCommand.ExecuteAsync(null);Check(!real.Usb!.Diagnostics.ReaderRunning,"Replay reader closes cleanly");
    }
}

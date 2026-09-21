using System.Collections.ObjectModel;
using AhaKey.Core;
using System.Windows;
using AhaKey.Device;
using AhaKey.Device.Ble;
using AhaKey.Device.Usb;
using AhaKey.Services;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
namespace AhaKey.Studio.ViewModels;
public sealed record BleRow(string Label,string Value);
public sealed partial class BleViewModel : ObservableObject
{
    public AppVersionService Version=>AppVersionService.Current;
    public string SupportInformation=>Version.SupportText;
    public Func<object?>? ProductDiagnostics {get;set;}
    public string DiagnosticExport=>System.Text.Json.JsonSerializer.Serialize(new {Product=Version.ProductName,Version=Version.Version,Version.InformationalVersion,Version.Build,FirmwareIdentity=manager.RealDevice?.FirmwareIdentity,Readiness=manager.RealDevice?.Readiness,CapabilityGates=controls.DiagnosticGates,
        Features=new[]{controls.Features.CanWriteShortcut(HardwareProfileId.Codex,PhysicalKey.K2),controls.Features.CanUseRuntimeLighting(1),controls.Features.CanSetBrightness(),controls.Features.CanUploadDisplay(HardwareProfileId.Codex,DisplayState.Default,8),controls.Features.CanReadConfigResource(0),controls.Features.FullReadback},
        Transport=TransportName,Live=Observation.IsLive,Session=Observation.SessionId,LastStatusAt=Observation.StatusAt,ErrorKey=Observation.ErrorKey,LastOperation=manager.Operations.Current??manager.Operations.Journal.LastOrDefault(),LastCrash=Services.CrashEvidence.LastReport,ProductState=ProductDiagnostics?.Invoke()},new System.Text.Json.JsonSerializerOptions{WriteIndented=true});
    private readonly DeviceManager manager;
    private readonly ProfileSelectionService preferences;
    private readonly RealDeviceRuntime runtime;
    private readonly Services.PhysicalControlRuntime controls;
    private CancellationTokenSource? operation;
    private bool fresh;
    public LocalizationService L {get;}
    public ObservableCollection<BleDeviceInfo> Devices {get;}=[];
    [ObservableProperty] private BleDeviceInfo? selected;
    [ObservableProperty] private bool busy;
    [ObservableProperty] private string? errorKey;
    [ObservableProperty] private bool copied;
    public BleViewModel(DeviceManager manager,ProfileSelectionService preferences,LocalizationService l,RealDeviceRuntime runtime,Services.PhysicalControlRuntime controls)
    {
        this.controls=controls;controls.Changed+=Refresh;this.manager=manager;this.preferences=preferences;L=l;this.runtime=runtime;runtime.Changed+=Refresh;
        if(preferences.Settings.BleDeviceId is {} id)
        {selected=new(id,preferences.Settings.BleDeviceName??"AhaKey",preferences.Settings.BleDeviceAddress);Devices.Add(selected);if(manager.RealDevice is {} real)real.Selected=selected;}
        if(manager.RealDevice is {} d)d.Changed+=Refresh;
        manager.Changed+=Refresh;L.PropertyChanged+=(_,_)=>Refresh();
        var clock=new System.Windows.Threading.DispatcherTimer{Interval=TimeSpan.FromSeconds(5)};
        clock.Tick+=(_,_)=>Refresh();clock.Start();
    }
    public bool RedactIdentity {get;set;}
    public BleDiagnostics Snapshot=>manager.RealDevice?.Diagnostics??new();
    private PhysicalObservation Observation=>manager.RealDevice?.Observation??new(PhysicalTransportKind.Bluetooth,null,false,null,null,null,null);
    private UsbDiagnostics UsbSnapshot=>manager.RealDevice?.Usb?.Diagnostics??new();
    public bool IsUsb=>manager.RealDevice?.ActiveTransport==PhysicalTransportKind.Usb;
    public bool IsBluetooth=>!IsUsb;
    public string TransportName=>IsUsb?"USB":"Bluetooth";
    public string CatalogLabel=>L[IsUsb?"UsbCatalog":"BleCatalog"];
    public string DeviceName=>IsUsb?L["UsbDeviceName"]:Selected?.Name??"AhaKey";
    public string TransportHint=>L[IsUsb?"UsbExplicitHint":"AlphaPickerHint"];
    public string CandidateMessage=>!IsUsb?"":L[HidSelectionPolicy.Select(UsbSnapshot.Candidates).ErrorKey??"UsbIdentified"];
    public bool CanChooseTransport=>IsReal && !IsWorking;
    public bool IsReal=>manager.RealBackendSelected;
    public bool IsWorking=>Busy || runtime.Busy || controls.UsbOperationBusy;
    public bool ShowPicker=>!Observation.IsLive;
    public bool ShowBluetoothPicker=>ShowPicker && IsBluetooth;
    public bool ShowUsbPicker=>ShowPicker && IsUsb;
    public bool HasSelection=>IsUsb?UsbSnapshot.Selected is not null || UsbSnapshot.Candidates.Count>0:Selected is not null;
    public bool CanForget=>IsBluetooth && HasSelection && !IsWorking;
    public bool CanFind=>IsReal && !IsWorking && manager.RealDevice is not null && !Observation.IsLive;
    public bool CanConnect=>CanFind && (IsUsb?HidSelectionPolicy.Select(UsbSnapshot.Candidates).Candidate is not null:Selected is not null);
    public bool CanRead=>IsReal && !IsWorking && Observation.IsLive;
    public bool CanDisconnect=>IsReal && (IsWorking || Observation.IsLive || (IsUsb && UsbSnapshot.ReaderRunning));
    public string Stage=>IsUsb?(runtime.Busy?L["BleStageAcquiringLink"]:UsbSnapshot.IsLive?L["UsbConnected"]:L[UsbSnapshot.ErrorKey??"BleStageDisconnected"]):runtime.Busy?L[runtime.Reconnecting?"BleStageReconnecting":"BleStageAcquiringLink"]:
        Snapshot.IsLive?L["AlphaConnected"]:Snapshot.ErrorKey is "BleAdapterUnavailable"?L["AlphaBluetoothUnavailable"]:
        Snapshot.ErrorKey is not null && Snapshot.ErrorKey!="ErrorCancelled"?L["AlphaUnavailable"]:L["BleStage"+Snapshot.Stage];
    public bool Fresh=>fresh;
    public string Freshness=>Observation.StatusAt is {} at ? $"{TransportName} · {L[Fresh?"BleLive":"BleStale"]} · {at.ToLocalTime():yyyy-MM-dd HH:mm:ss zzz}" : L["BleUnknown"];
    public string Compatibility=>(Observation.Status is null?CompatibilityState.Unknown:CompatibilityState.LegacyTelemetryOnly).ToString();
    public string? Error=>(ErrorKey??Observation.ErrorKey) is {} key?L[key is "BleGattFailure" or "BleAcquireFailure" or "BleLinkLost" or "BleQueryTimeout"?"AlphaReconnectHint":key]:null;
    public string CopyLabel=>L[Copied?"BleCopied":"BleCopy"];
    public string SelectedIdentity=>Selected is null?L["BleChoose"]:RedactIdentity?L["BleIdentityHidden"]:$"{Selected.Id}\n{Selected.Address??L["BleUnavailable"]}";
    private string Value(object? value)=>value?.ToString()??L["BleUnknown"];
    private string Flag(bool? value)=>value is null?L["BleUnknown"]:L[value.Value?"BleYes":"BleNo"];
    private IReadOnlyList<BleRow> UsbDetails=>[new(L["AlphaTransport"],"USB"),new(L["BleSession"],Value(Observation.SessionId)),new(L["UsbReader"],L[UsbSnapshot.ReaderRunning?"UsbReaderRunning":"UsbReaderStopped"]),new(L["AlphaCompatibility"],Compatibility),new(L["AlphaLastStatus"],UsbSnapshot.LastStatusQuery is {} status?$"00 · {status.ResponseAt.ToLocalTime():HH:mm:ss}":L["BleUnknown"]),new(L["BleLastQuery"],UsbSnapshot.LastQuery is {} q?$"{(byte)q.Command:X2} · {q.ResponseAt.ToLocalTime():HH:mm:ss}":L["BleUnknown"]),new(L["BleLastError"],Error??L["BleNone"])];
    private IReadOnlyList<BleRow> UsbAdvancedDetails
    {
        get
        {
            var d=UsbSnapshot;var c=d.Selected;var q=d.LastQuery;
            return [new("VID / PID",c is null?L["BleUnknown"]:$"{c.Vid:X4} / {c.Pid:X4}"),new(L["UsbCollection"],c is null?L["BleUnknown"]:$"MI {c.InterfaceNumber?.ToString("X2")??"—"} / COL {c.Collection?.ToString("X2")??"—"}; usage {c.UsagePage:X4}:{c.Usage:X4}"),
                new(L["UsbLengths"],c is null?L["BleUnknown"]:$"IN {c.InputLength} / OUT {c.OutputLength} / FEATURE {c.FeatureLength}"),new(L["UsbReportPolicy"],L["UsbReportPolicyValue"]),
                new(L["UsbOutput"],d.LastOutput.IsEmpty?L["BleUnknown"]:Convert.ToHexString(d.LastOutput.AsSpan())),new(L["UsbInput"],d.LastInput.IsEmpty?L["BleUnknown"]:Convert.ToHexString(d.LastInput.AsSpan())),
                new(L["UsbFrame"],q is null?L["BleUnknown"]:Convert.ToHexString(q.Frame.AsSpan())),new(L["UsbWriteResult"],d.LastWriteResult is not {} result?L["BleUnknown"]:$"{result.Success}; {result.BytesWritten} / {d.LastOutput.Length}; error {result.Error}"),
                new(L["BleTiming"],q is null?L["BleUnknown"]:$"TX {q.WriteStartedAt:HH:mm:ss.fff}; completed {q.WriteCompletedAt:HH:mm:ss.fff}; RX {q.ResponseAt:HH:mm:ss.fff} UTC; {q.LatencyMs:F1} ms"),new(L["BleFirmwareSignal"],Value(d.Status?.FirmwareSignal)),new(L["BleBrightness"],Value(d.Status?.Brightness)),new(L["BleLastError"],d.Error??L["BleNone"])];
        }
    }
    public IReadOnlyList<BleRow> Summary
    {
        get
        {
            var d=Observation;var c=d.Capabilities;var s=d.Status;
            return [new(L["AlphaDeviceName"],DeviceName),new(L["AlphaTransport"],TransportName),new(L["BleConnection"],Stage),new(L["Battery"],s?.Battery is {} b?$"{b}%{(Fresh?"":" · "+L["BleStale"])}":L["BleUnknown"]),
                new(L["BleFirmware"],manager.RealDevice?.FirmwareIdentity.ReportedVersion??L["BleUnknown"]),
                new(L["FirmwareFamily"],L["Family"+(manager.RealDevice?.FirmwareIdentity.Dialect??FirmwareDialect.Unknown)]),
                new(L["FirmwareExactBuild"],manager.RealDevice?.FirmwareIdentity.KnownBuildHash??L["BleUnknown"]),
                new(L["BleContract"],L[c is null?"BleUnknown":c.SupportedContract?"BleSupported":c.ProtocolMajor is null?"BleLegacyIncomplete":"BleUnsupported"]),
                new(L["BleCapabilities"],c is null?L["BleUnknown"]:c.Bits is {} bits?$"0x{bits:X8}":L["BleNotReported"]),new(L["AlphaPhysicalMode"],Fresh?Value(s?.WorkMode):L["BleUnknown"]),
                new(L["AlphaConfirmation"],Fresh && s?.Confirmation is {} confirmation?L[confirmation.ToString()]:L["BleUnknown"]),new(L["AlphaConfiguration"],L[controls.Features.CanReadConfigResource(0).Available?"PartialKeyRead":"AlphaNoReadback"]),new(L["AlphaFirmwareUpdate"],L[manager.RealDevice?.FirmwareIdentity.Dialect==FirmwareDialect.WindowsContract32?"FirmwareTransportPrepared":"AlphaNoUpdate"]),new(L["AlphaLastTelemetry"],Freshness)];
        }
    }
    public IReadOnlyList<BleRow> ProductSummary=>Summary.Where(x=>x.Label!=L["BleContract"] && x.Label!=L["BleCapabilities"]).ToArray();
    public IReadOnlyList<BleRow> DiagnosticSummary=>Summary.Where(x=>new[]{L["AlphaDeviceName"],L["Battery"],L["BleFirmware"],L["FirmwareFamily"],L["FirmwareExactBuild"],L["BleCapabilities"]}.Contains(x.Label)).Concat(new BleRow[]{
        new("Dialect",Value(manager.RealDevice?.FirmwareIdentity.Dialect)),new("Identity evidence",Value(manager.RealDevice?.FirmwareIdentity.IdentitySource)),
        new("Behavior fingerprint",Value(manager.RealDevice?.FirmwareIdentity.ObservedBehaviorFingerprint)),
        new("BLE link",Flag(manager.RealDevice?.Readiness.BleLink)),new("GATT ready",Flag(manager.RealDevice?.Readiness.GattReady)),new("USB ready",Flag(manager.RealDevice?.Readiness.UsbReady)),new("HID ready",Flag(manager.RealDevice?.Readiness.HidReady)),new("Fresh telemetry",Flag(manager.RealDevice?.Readiness.FreshTelemetry)),new("Automatic telemetry polling",Flag(false))}).ToArray();
    public IReadOnlyList<BleRow> Details=>IsUsb?UsbDetails:[new(L["BleAdapter"],Value(Snapshot.Adapter.Name)),new(L["BleAdapterState"],L["BleAdapter"+Snapshot.Adapter.State]),new(L["BleSession"],Value(Snapshot.SessionId)),new(L["AlphaGattReady"],Flag(Snapshot.IsLive)),new(L["BleSubscribed"],Flag(Snapshot.Subscribed)),new(L["AlphaCompatibility"],Compatibility),new(L["AlphaLastStatus"],Snapshot.LastStatusQuery is {} status?$"00 · {status.ResponseAt.ToLocalTime():HH:mm:ss}":L["BleUnknown"]),new(L["BleLastQuery"],Snapshot.LastQuery is {} q?$"{(byte)q.Command:X2} · {q.ResponseAt.ToLocalTime():HH:mm:ss}":L["BleUnknown"]),new(L["BleTiming"],Snapshot.LastQuery is {} t?$"TX {t.WriteStartedAt.ToLocalTime():HH:mm:ss.fff} / RX {t.ResponseAt.ToLocalTime():HH:mm:ss.fff}":L["BleUnknown"]),new(L["BleReconnectAttempt"],Snapshot.ReconnectAttempt.ToString()),new(L["BleLastError"],Error??L["BleNone"])];
    public IReadOnlyList<BleRow> AdvancedDetails
    {
        get
        {
            var d=Snapshot;var q=d.LastQuery;
            if(IsUsb)return UsbAdvancedDetails;
            return [new(L["BleAdapter"],RedactIdentity?L["BleIdentityHidden"]:Value(d.Adapter.Name)),new(L["BleAdapterState"],L["BleAdapter"+d.Adapter.State]),new(L["BleDeviceId"],RedactIdentity?L["BleIdentityHidden"]:Value(d.Device?.Id)),new(L["BleAddress"],RedactIdentity?L["BleIdentityHidden"]:Value(d.Device?.Address)),
                new(L["BleNative"],Flag(d.NativeConnected)),new(L["BleSubscribed"],Flag(d.Subscribed)),new(L["BleSession"],Value(d.SessionId)),new(L["BleWindowsRssi"],L["BleUnavailable"]),new(L["BleFirmwareSignal"],Value(d.PhysicalStatus?.FirmwareSignal)),
                new(L["BleBrightness"],Value(d.PhysicalStatus?.Brightness)),new(L["BleReadiness"],Value(d.PhysicalStatus?.ReadinessFlags)),new(L["BleBits"],d.Capabilities?.Bits is {} bits?$"0x{bits:X8}":L[d.Capabilities is null?"BleUnknown":"BleNotReported"]),
                new(L["BleLastQuery"],q is null?L["BleUnknown"]:$"{(byte)q.Command:X2}"),new(L["BleTx"],d.LastTx.IsEmpty?L["BleUnknown"]:Convert.ToHexString(d.LastTx.AsSpan())),new(L["BleGattResult"],d.LastGattResult is {} r?$"{r.Status}; ATT={r.ProtocolError?.ToString("X2")??"—"}":L["BleUnknown"]),
                new(L["BleRx"],d.LastRx.IsEmpty?L["BleUnknown"]:Convert.ToHexString(d.LastRx.AsSpan())),new(L["BleTiming"],q is null?L["BleUnknown"]:$"TX {q.WriteStartedAt:HH:mm:ss.fff}; RX {q.ResponseAt:HH:mm:ss.fff}; GATT {q.WriteCompletedAt:HH:mm:ss.fff} UTC; TX–RX {q.LatencyMs:F1} ms"),
                new(L["BleReconnectAttempt"],d.ReconnectAttempt.ToString()),new(L["BleLastError"],d.Error??L["BleNone"])];
        }
    }
    public string Catalog=>IsUsb?System.Text.Json.JsonSerializer.Serialize(UsbSnapshot.Candidates.Select(UsbDiagnosticExport.Candidate),new System.Text.Json.JsonSerializerOptions{WriteIndented=true}):Snapshot.Catalog.IsEmpty?L["BleUnknown"]:string.Join("\n",Snapshot.Catalog.Select(s=>$"{s.Uuid} [{s.Result.Status}]\n"+string.Join("\n",s.Characteristics.Select(c=>$"  {c.Uuid}  {c.Properties}"))));
    public string History=>IsUsb?string.Join("\n",UsbSnapshot.History.Select(h=>$"{h.At:HH:mm:ss.fff} {h.Event} {h.Detail}")):string.Join("\n",Snapshot.History.Select(h=>$"{h.At:HH:mm:ss.fff} {h.Session?.ToString()[..8]??"—"} {h.Event} {h.Detail}"));
    partial void OnSelectedChanged(BleDeviceInfo? value)
    {
        if(value is null)return;
        if(manager.RealDevice is {} d)d.Selected=value;
        try {preferences.Update(s=>s with{BleDeviceId=value.Id,BleDeviceName=value.Name,BleDeviceAddress=value.Address});ErrorKey=null;}
        catch(Exception ex) when(ex is System.IO.IOException or UnauthorizedAccessException){ErrorKey="SettingsSaveError";}
        Refresh();
    }
    private async Task Run(Func<CancellationToken,Task> action)
    {
        if(Busy)return;using var owner=new CancellationTokenSource();operation=owner;Busy=true;ErrorKey=null;Refresh();
        try {await action(owner.Token);}
        catch(Exception ex){ErrorKey=ex is UsbException u?u.Key:ex is BleException b?b.Key:ex is OperationCanceledException?"ErrorCancelled":"BleNativeFailure";}
        finally {operation=null;Busy=false;Refresh();}
    }
    [RelayCommand] private Task FindAsync()=>Run(async ct=>{if(IsUsb){await manager.RealDevice!.Usb!.DiscoverAsync(ct);return;}var found=await manager.RealDevice!.DiscoverAsync(ct);Devices.Clear();foreach(var d in found.Where(x=>x.Name.StartsWith("AhaKey",StringComparison.OrdinalIgnoreCase)))Devices.Add(d);});
    [RelayCommand] private Task ChooseUsbAsync()=>IsUsb?Task.CompletedTask:Run(async ct=>{await runtime.SelectTransportAsync(PhysicalTransportKind.Usb);await manager.RealDevice!.Usb!.DiscoverAsync(ct);});
    [RelayCommand] private Task ChooseBluetoothAsync()=>IsBluetooth?Task.CompletedTask:Run(_=>runtime.SelectTransportAsync(PhysicalTransportKind.Bluetooth));
    [RelayCommand] private Task ConnectAsync()=>Run(_=>runtime.ConnectAsync());
    [RelayCommand] private Task ReadAsync()=>Run(manager.ReadAsync);
    [RelayCommand] private Task ReconnectAsync()=>Run(_=>runtime.ConnectAsync(true));
    [RelayCommand] private async Task DisconnectAsync(){operation?.Cancel();await runtime.DisconnectAsync();ErrorKey=null;Refresh();}
    [RelayCommand] private async Task ForgetAsync()
    {
        await DisconnectAsync();
        try{preferences.Update(s=>s with{BleDeviceId=null,BleDeviceName=null,BleDeviceAddress=null});Selected=null;Devices.Clear();if(manager.RealDevice is {} d)d.Selected=null;}
        catch(Exception ex) when(ex is System.IO.IOException or UnauthorizedAccessException){ErrorKey="SettingsSaveError";}
        Refresh();
    }
    public void ReportFailure(Exception ex){ErrorKey=ex is BleException b?b.Key:"BleNativeFailure";Refresh();}
    [RelayCommand] private void Copy(){try{Clipboard.SetText(DiagnosticExport);Copied=true;}catch(System.Runtime.InteropServices.COMException){ErrorKey="BleCopyFailed";}Refresh();}
    public void Refresh()
    {
        var dispatcher=Application.Current?.Dispatcher;if(dispatcher is null || dispatcher.HasShutdownStarted)return;
        if(!dispatcher.CheckAccess()){dispatcher.BeginInvoke(Refresh);return;}
        // All bindings in this UI refresh share one freshness decision, including the header.
        // Re-reading the clock in each getter can straddle the 60-second boundary mid-render.
        var observed=Observation;
        fresh=observed.IsLive && observed.StatusAt is {} at && DateTimeOffset.UtcNow-at<TimeSpan.FromSeconds(60);
        foreach(var name in new[]{nameof(IsUsb),nameof(IsBluetooth),nameof(DeviceName),nameof(TransportName),nameof(CatalogLabel),nameof(TransportHint),nameof(CandidateMessage),nameof(CanChooseTransport),nameof(ShowBluetoothPicker),nameof(ShowUsbPicker)})OnPropertyChanged(name);
        foreach(var name in new[]{nameof(IsReal),nameof(IsWorking),nameof(ShowPicker),nameof(HasSelection),nameof(CanForget),nameof(CanFind),nameof(CanConnect),nameof(CanRead),nameof(CanDisconnect),nameof(Stage),nameof(Freshness),nameof(Error),nameof(CopyLabel),nameof(SelectedIdentity),nameof(ProductSummary),nameof(Summary),nameof(Details),nameof(AdvancedDetails),nameof(DiagnosticSummary),nameof(Compatibility),nameof(Catalog),nameof(History)})OnPropertyChanged(name);
    }
}

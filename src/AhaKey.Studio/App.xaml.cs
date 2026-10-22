using System.IO;
using System.Windows;
using AhaKey.Core;
using AhaKey.Device;
using AhaKey.Device.Ble;
using AhaKey.Device.Usb;
using AhaKey.Services;
using AhaKey.Studio.Services;
using AhaKey.Studio.ViewModels;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
namespace AhaKey.Studio;
public partial class App : Application
{
    private IHost? host;
    private SingleInstanceOwner? instance;
    private ILogger? logger;
    private TrayLifetime? tray;
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        AppDomain.CurrentDomain.UnhandledException+=(_,args)=>{if(args.ExceptionObject is Exception ex)CrashEvidence.Record(ex,"AppDomain");};
        TaskScheduler.UnobservedTaskException+=(_,args)=>CrashEvidence.Record(args.Exception,"TaskScheduler");
        DispatcherUnhandledException+=(_,args)=>CrashEvidence.Record(args.Exception,"Dispatcher");
        try
        {
            if(e.Args.Length==2 && e.Args[0]=="--phase9-key-observation")
            {
                ShutdownMode=ShutdownMode.OnExplicitShutdown;
                try{await Phase9BleAcceptance.ObserveKeysAsync(e.Args[1]);Shutdown(0);}
                catch(Exception ex){File.WriteAllText(Path.Combine(e.Args[1],"observation-error.txt"),ex.ToString());Shutdown(2);}return;
            }
            if(e.Args.Length==2 && e.Args[0]=="--phase9-display-acceptance")
            {
                ShutdownMode=ShutdownMode.OnExplicitShutdown;
                try{await Phase9DisplayAcceptance.RunAsync(e.Args[1]);Shutdown(0);}
                catch(Exception ex){File.WriteAllText(Path.Combine(e.Args[1],"error.txt"),ex.ToString());Shutdown(2);}return;
            }
            if(e.Args.Length==2 && e.Args[0]=="--phase9-ble-acceptance")
            {
                ShutdownMode=ShutdownMode.OnExplicitShutdown;
                try{await Phase9BleAcceptance.RunAsync(e.Args[1]);Shutdown(0);}
                catch(Exception ex){Directory.CreateDirectory(e.Args[1]);File.WriteAllText(Path.Combine(e.Args[1],"error.txt"),ex.ToString());Shutdown(2);}return;
            }
            if(e.Args.Length==2 && e.Args[0]=="--installer-cleanup")
            {ShutdownMode=ShutdownMode.OnExplicitShutdown;Shutdown(InstallerCleanup.Run(int.TryParse(e.Args[1],out var uiLevel)&&uiLevel>=3));return;}
            if(e.Args.Length==2 && e.Args[0]=="--firmware-worker")
            {
                ShutdownMode=ShutdownMode.OnExplicitShutdown;
                try{Shutdown(await WchProcessRunner.RunWorkerAsync(e.Args[1]));}
                catch(Exception ex){CrashEvidence.Record(ex,"Firmware worker stopped");Shutdown(2);}return;
            }
            if(e.Args.Length==3 && e.Args[0] is "--phase61-ble-rgb-trial" or "--phase61-promote-ble")
            {
                ShutdownMode=ShutdownMode.OnExplicitShutdown;
                try{if(e.Args[0]=="--phase61-ble-rgb-trial")await Phase61BleRgbTrial.RunAsync(e.Args[1],e.Args[2]);else Phase61BleRgbTrial.Promote(e.Args[1],e.Args[2]);Shutdown(0);}
                catch(Exception ex){Directory.CreateDirectory(e.Args[1]);File.WriteAllText(Path.Combine(e.Args[1],"error.txt"),ex.GetType().Name+": "+ex.Message);Shutdown(2);}return;
            }
            if(e.Args.Length==3 && e.Args[0]=="--phase6-profile-trial")
            {
                ShutdownMode=ShutdownMode.OnExplicitShutdown;
                try{await Phase6ProfileTrial.RunAsync(e.Args[1],e.Args[2]);Shutdown(0);}
                catch(Exception ex){Directory.CreateDirectory(e.Args[1]);File.WriteAllText(Path.Combine(e.Args[1],"error.txt"),ex.GetType().Name+": "+ex.Message);Shutdown(2);}return;
            }
            if(e.Args.Length==4 && e.Args[0]=="--phase5-display-trial")
            {
                ShutdownMode=ShutdownMode.OnExplicitShutdown;
                try{await Phase5DisplayAcceptance.RunAsync(e.Args[1],e.Args[2],e.Args[3]);Shutdown(0);}
                catch(Exception ex){Directory.CreateDirectory(e.Args[1]);File.WriteAllText(Path.Combine(e.Args[1],"acceptance-error.txt"),ex is InvalidOperationException?ex.Message:ex.GetType().Name+": stopped without retry; inspect native ledger.");Shutdown(2);}return;
            }
            if(e.Args.Length==2 && e.Args[0]=="--phase5-rgb-live")
            {
                ShutdownMode=ShutdownMode.OnExplicitShutdown;
                try{await Phase5RgbAcceptance.RunAsync(e.Args[1]);Shutdown(0);}
                catch(Exception ex){Directory.CreateDirectory(e.Args[1]);File.WriteAllText(Path.Combine(e.Args[1],"acceptance-error.txt"),ex is InvalidOperationException?ex.Message:ex.GetType().Name+": stopped without retry; inspect native ledger.");Shutdown(2);}return;
            }
            if(e.Args.Length==3 && e.Args[0]=="--phase5-k1-trial")
            {
                ShutdownMode=ShutdownMode.OnExplicitShutdown;
                try{await K1PhysicalAcceptance.RunAsync(e.Args[1],e.Args[2]);Shutdown(0);}
                catch(Exception ex){Directory.CreateDirectory(e.Args[1]);File.WriteAllText(Path.Combine(e.Args[1],"acceptance-error.txt"),ex is InvalidOperationException?ex.Message:ex.GetType().Name+": stopped without retry; inspect ledger and restore evidence.");Shutdown(2);}return;
            }
            if(e.Args.Length==2 && e.Args[0]=="--default-bindings-ad1e")
            {
                ShutdownMode=ShutdownMode.OnExplicitShutdown;
                try{await DefaultBindingsCapture.RunAsync(e.Args[1]);Shutdown(0);}
                catch(Exception ex){Directory.CreateDirectory(e.Args[1]);File.WriteAllText(Path.Combine(e.Args[1],"capture-error.txt"),ex is InvalidOperationException?ex.Message:ex.GetType().Name+": stopped without retry.");Shutdown(2);}return;
            }
            if(e.Args.Length==3 && e.Args[0] is "--physical-lighting-acceptance" or "--physical-lighting-visual-trial")
            {
                ShutdownMode=ShutdownMode.OnExplicitShutdown;
                try{await PhysicalControlsAcceptance.RunLightingAsync(e.Args[1],e.Args[2],e.Args[0]=="--physical-lighting-visual-trial");Shutdown(0);}
                catch(Exception ex){Directory.CreateDirectory(e.Args[1]);File.WriteAllText(Path.Combine(e.Args[1],"acceptance-error.txt"),ex is InvalidOperationException?ex.Message:ex.GetType().Name+": stopped without retry; inspect ledger.");Shutdown(2);}return;
            }
            if(e.Args.Length is 2 or 3 && e.Args[0]=="--physical-key-acceptance")
            {
                ShutdownMode=ShutdownMode.OnExplicitShutdown;
                try{await PhysicalControlsAcceptance.RunAsync(e.Args[1],e.Args.Length==3?e.Args[2]:null);Shutdown(0);}
                catch(Exception ex){Directory.CreateDirectory(e.Args[1]);File.WriteAllText(Path.Combine(e.Args[1],"acceptance-error.txt"),ex is InvalidOperationException?ex.Message:ex.GetType().Name+": stopped without retry; inspect ledger.");Shutdown(2);}return;
            }
            if(e.Args.Length==2 && e.Args[0] is "--integration-configure-codex" or "--integration-remove-codex")
            {await CodexAcceptance.ConfigureAsync(Path.GetFullPath(e.Args[1]),e.Args[0]=="--integration-remove-codex");Shutdown(0);return;}
            if(e.Args.Length==2 && e.Args[0]=="--integration-inspect-preview")
            {await IntegrationsSmoke.InspectHostAsync(Path.GetFullPath(e.Args[1]));Shutdown(0);return;}
            if(e.Args.Length==2 && e.Args[0]=="--display-characterize-ad1e")
            {
                try{await DisplayCharacterizationCapture.RunAsync(e.Args[1]);Shutdown(0);}
                catch(Exception ex){Directory.CreateDirectory(Path.GetFullPath(e.Args[1]));File.WriteAllText(Path.Combine(Path.GetFullPath(e.Args[1]),"capture-error.txt"),ex.GetType().Name+": "+(ex is InvalidOperationException?ex.Message:"Capture stopped; no retry. Inspect preserved events."));Shutdown(2);}
                return; // Explicit USB-only one-shot; no host/BLE startup, settings load or normal UI.
            }
            if(e.Args.Length==2 && e.Args[0]=="--usb-inspect")
            {
                var candidates=await new WindowsHidSessionFactory().EnumerateAsync(default);
                Directory.CreateDirectory(Path.GetFullPath(e.Args[1]));
                File.WriteAllText(Path.Combine(Path.GetFullPath(e.Args[1]),"hid-candidates.json"),UsbDiagnosticExport.Redacted(new(){Candidates=candidates}));
                var proofPath=Path.Combine(new SettingsStore().Root,"physical-controls-acceptance.json");
                var proof=File.Exists(proofPath)?System.Text.Json.JsonSerializer.Deserialize<ControlAcceptance>(File.ReadAllText(proofPath)):null;
                var candidate=HidSelectionPolicy.Select(candidates).Candidate;
                bool matches=candidate is not null && proof?.DeviceHash==Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes("Usb:"+candidate.Path)));
                File.WriteAllText(Path.Combine(Path.GetFullPath(e.Args[1]),"acceptance-gates.json"),System.Text.Json.JsonSerializer.Serialize(new{MetadataOnly=true,PrivateUsbReceiptPresent=proof is not null,StoredFirmware=proof?.Firmware,KeyVerified=proof?.KeyBehaviorVerified,StoredEffects=proof?.VisuallyVerifiedEffects.Select(x=>(int)x).ToArray(),UniqueUsbCandidate=candidate is not null,UsbIdentityMatches=matches}));
                Shutdown(0);return; // Metadata-only; never opens an I/O session or sends a device command.
            }
            if(e.Args.Length is 3 or 4 && e.Args[0]=="--phase8-repro"){Phase8Repro.Output=e.Args[1];Phase8Repro.Scenario=e.Args[2];Phase8Repro.Fixture=e.Args.Length==4?e.Args[3]:null;Directory.CreateDirectory(e.Args[1]);}
            var integrationAcceptance=e.Args.Length==2 && e.Args[0]=="--integration-acceptance";
            var integrationsSmoke=e.Args.Length==2 && e.Args[0]=="--integrations-smoke";
            var hardware=e.Args.Length==3 && e.Args[0]=="--ble-acceptance";
            var legacySmoke=e.Args.Length==2 && e.Args[0]=="--legacy-diagnostics-smoke";
            var phase9Smoke=e.Args.Length==2 && e.Args[0]=="--phase9-runtime-smoke";
            var productSmoke=phase9Smoke || Phase8Repro.Output is not null || e.Args.Length==2 && e.Args[0]=="--product-smoke";
            var usbSmoke=productSmoke || e.Args.Length==2 && e.Args[0]=="--usb-diagnostics-smoke";
            var smoke = e.Args.Length == 2 && e.Args[0] == "--smoke-test";
            var root = smoke || hardware || legacySmoke || usbSmoke || integrationsSmoke || integrationAcceptance ? Path.Combine(Path.GetFullPath(e.Args[1]), "isolated-settings", Guid.NewGuid().ToString("N")) : null;
            var settingsStore=new SettingsStore(root);CrashEvidence.Configure(settingsStore.Root);
            if(smoke || integrationsSmoke || integrationAcceptance)settingsStore.Save(new(Backend:BackendChoice.Mock){DeveloperMode=true});
            if(!smoke && !hardware && !legacySmoke && !usbSmoke && !integrationsSmoke && !integrationAcceptance)
            {
                instance=new(settingsStore.Root);
                if(!instance.IsPrimary){await instance.ActivateAsync();Shutdown(0);return;}
                instance.ActivationRequested+=()=>Dispatcher.BeginInvoke(()=>
                {if(tray is not null)tray.Show();else if(MainWindow is {} window){if(window.WindowState==WindowState.Minimized)window.WindowState=WindowState.Normal;window.Show();window.Activate();}});
            }
            var builder = Host.CreateApplicationBuilder(new HostApplicationBuilderSettings { DisableDefaults = true });
            builder.Services.AddSingleton(settingsStore);
            builder.Services.AddSingleton<LocalDraftStore>();
            builder.Services.AddSingleton<LocalDeviceProjectStore>();builder.Services.AddSingleton<LocalProjectRuntime>();
            builder.Services.AddSingleton<OperationJournalStore>();builder.Services.AddSingleton<ProjectViewModel>();builder.Services.AddSingleton<VoiceRoutingRuntime>();
            if(productSmoke)builder.Services.AddSingleton<ProductDialogs,ProductReplayDialogs>();else builder.Services.AddSingleton<ProductDialogs>();
            builder.Services.AddSingleton<ProductWriteHistory>();builder.Services.AddSingleton<ProfileActivationRuntime>();
            builder.Services.AddSingleton<ProfileSelectionService>(); builder.Services.AddSingleton<LocalizationService>();
            builder.Services.AddSingleton<ThemeService>(); builder.Services.AddSingleton<SessionLogProvider>();
            builder.Services.AddSingleton<ILoggerProvider>(s => s.GetRequiredService<SessionLogProvider>());
            builder.Services.AddLogging(logging=>logging.AddFilter("Microsoft.Hosting.Lifetime",LogLevel.Warning)); builder.Services.AddSingleton<ConfigurationChangeTracker>();
            builder.Services.AddSingleton<MockAhaKeyDevice>(); builder.Services.AddSingleton<IAhaKeyDevice>(s => s.GetRequiredService<MockAhaKeyDevice>());
            if(!smoke) {
                if(legacySmoke || usbSmoke)builder.Services.AddSingleton<IWindowsGattSessionFactory,LegacyDiagnosticsFactory>();
                else builder.Services.AddSingleton<IWindowsGattSessionFactory,WindowsGattSessionFactory>();
                builder.Services.AddSingleton(GattContract.WindowsObserved);builder.Services.AddSingleton<BleTransport>();
                if(usbSmoke){builder.Services.AddSingleton<UsbReplayFactory>();builder.Services.AddSingleton<IWindowsHidSessionFactory>(s=>s.GetRequiredService<UsbReplayFactory>());}
                else builder.Services.AddSingleton<IWindowsHidSessionFactory,WindowsHidSessionFactory>();
                builder.Services.AddSingleton<UsbTransport>();
                builder.Services.AddSingleton<RealAhaKeyDevice>();
            }
            builder.Services.AddSingleton<FirmwareRuntime>();builder.Services.AddSingleton<FirmwareViewModel>();
            builder.Services.AddSingleton<PhysicalControlRuntime>();builder.Services.AddSingleton<ControlsViewModel>();builder.Services.AddSingleton<DisplayPlannerViewModel>();
            builder.Services.AddSingleton<IntegrationRuntime>();builder.Services.AddSingleton<IntegrationsViewModel>();
            builder.Services.AddSingleton<BleViewModel>();builder.Services.AddSingleton<DeviceManager>();builder.Services.AddSingleton<RealDeviceRuntime>(); builder.Services.AddSingleton<ProfilesViewModel>();
            builder.Services.AddSingleton<KeymapViewModel>(); builder.Services.AddSingleton<SettingsViewModel>(); builder.Services.AddSingleton<ShellViewModel>(); builder.Services.AddSingleton<MainWindow>();
            host = builder.Build(); await host.StartAsync();
            logger=host.Services.GetRequiredService<ILoggerFactory>().CreateLogger("Runtime");
            logger.LogInformation("Startup {Product}; Version {Version}; Build {Build}; {Platform}",AppVersionService.Current.ProductName,AppVersionService.Current.Version,AppVersionService.Current.Build,AppVersionService.Current.Platform);
            var settings = host.Services.GetRequiredService<ProfileSelectionService>().Settings;
            host.Services.GetRequiredService<LocalizationService>().Apply(settings.Language);
            host.Services.GetRequiredService<ThemeService>().Apply(settings.Theme);
            var manager = host.Services.GetRequiredService<DeviceManager>();
            SessionEnding+=(_,args)=>{if(manager.Operations.Current is {Persistent:true})args.Cancel=true;};
            await manager.SelectBackendAsync(!smoke && settings.EffectiveBackend == BackendChoice.Real);
            logger.LogInformation("Backend {Backend}",manager.RealBackendSelected?"Real BLE":"Mock Simulation");
            var drafts=host.Services.GetRequiredService<LocalDraftStore>();
            if(drafts.Load() is {} draft)manager.Edit(draft);
            host.Services.GetRequiredService<LocalProjectRuntime>().Initialize();
            var operationJournal=host.Services.GetRequiredService<OperationJournalStore>();
            foreach(var entry in operationJournal.Read<DeviceOperationRecord>().Where(x=>x.Outcome==OperationOutcome.Running))operationJournal.Persist(entry.Id,DeviceOperationCoordinator.Recover(entry));
            manager.Operations.Persist=entry=>operationJournal.Persist(entry.Id,entry);
            var savedDraft=manager.Tracker.Draft;
            manager.Changed+=()=>{var current=manager.Tracker.Draft;if(!ReferenceEquals(savedDraft,current)){drafts.Save(current);savedDraft=current;}};
            if(manager.RealDevice is {} physical)physical.Transport.OperationalEvent+=ev=>logger.LogInformation("BLE {Session} {Event} {Detail}",ev.Session,ev.Event,ev.Detail);
            if(manager.RealDevice?.Usb is {} usb)usb.OperationalEvent+=ev=>logger.LogInformation("USB {Session} {Event} {Detail}",ev.Session,ev.Event,ev.Detail);
            var runtime=host.Services.GetRequiredService<RealDeviceRuntime>();
            MainWindow = host.Services.GetRequiredService<MainWindow>();
            var integrations=host.Services.GetRequiredService<IntegrationRuntime>();
            Views.IntegrationApprovalWindow? approvalWindow=null;
            integrations.Manager.Approvals.PendingChanged+=request=>Dispatcher.BeginInvoke(()=>
            {
                approvalWindow?.Close();approvalWindow=null;
                if(request is not null && !request.Decision.IsCompleted){approvalWindow=new(request,host.Services.GetRequiredService<LocalizationService>()){Owner=MainWindow};approvalWindow.Show();}
            });
            var normalRun=!smoke&&!productSmoke&&!usbSmoke&&!legacySmoke&&!integrationsSmoke&&!hardware&&!integrationAcceptance;
            if(normalRun)
            {
                ShutdownMode=ShutdownMode.OnExplicitShutdown;
                tray=new TrayLifetime(MainWindow,host.Services.GetRequiredService<ShellViewModel>(),host.Services.GetRequiredService<ProfileSelectionService>(),integrations,runtime,async()=>
                {
                    await integrations.DisposeAsync();await runtime.DisconnectAsync();
                    if(manager.RealDevice is {} real)await real.DisposeAsync();
                    logger.LogInformation("Exit: sessions released");
                });
            }
            if(Phase8Repro.Output is not null && Phase8Repro.Scenario!="manual")
            {MainWindow.ShowActivated=false;MainWindow.ShowInTaskbar=false;MainWindow.WindowStartupLocation=WindowStartupLocation.Manual;MainWindow.Left=-10000;MainWindow.Top=-10000;}
            if(normalRun && e.Args.Contains("--tray"))
            {
                MainWindow.ShowActivated=false;MainWindow.ShowInTaskbar=false;
                new System.Windows.Interop.WindowInteropHelper(MainWindow).EnsureHandle();
                host.Services.GetRequiredService<ShellViewModel>().DisplayPlanner.SetPreviewVisible(false);
            }
            else {MainWindow.Show();host.Services.GetRequiredService<ShellViewModel>().DisplayPlanner.SetPreviewVisible(true);}
            if(!smoke&&!productSmoke&&!usbSmoke&&!legacySmoke&&!integrationsSmoke&&!hardware&&!integrationAcceptance)host.Services.GetRequiredService<VoiceRoutingRuntime>().Attach(MainWindow);
            if(integrationAcceptance){await CodexAcceptance.RunUiAsync(MainWindow,host.Services,Path.GetFullPath(e.Args[1]));Shutdown(0);}
            if(integrationsSmoke){await IntegrationsSmoke.RunAsync(MainWindow,host.Services,Path.GetFullPath(e.Args[1]));Shutdown(0);}
            if(legacySmoke){await LegacyDiagnosticsSmoke.RunAsync(MainWindow,host.Services,Path.GetFullPath(e.Args[1]));Shutdown(0);}
            if(usbSmoke){if(phase9Smoke)await Phase9RuntimeSmoke.RunAsync(MainWindow,host.Services,Path.GetFullPath(e.Args[1]));else if(Phase8Repro.Output is not null)await Phase8Repro.RunAsync(MainWindow,host.Services);else if(productSmoke)await ProductSmoke.RunAsync(MainWindow,host.Services,Path.GetFullPath(e.Args[1]));else await UsbDiagnosticsSmoke.RunAsync(MainWindow,host.Services,Path.GetFullPath(e.Args[1]));Shutdown(0);}
            if(!smoke && !hardware && !legacySmoke && !usbSmoke && !integrationsSmoke && !integrationAcceptance){await runtime.StartAsync();await host.Services.GetRequiredService<IntegrationRuntime>().InitializeAsync();}
            if(hardware){await BleHardwareAcceptance.RunAsync(MainWindow,host.Services,Path.GetFullPath(e.Args[1]),e.Args[2]);Shutdown(0);}
            if (smoke)
            {
                await StudioSmokeTest.RunAsync(MainWindow, host.Services, Path.GetFullPath(e.Args[1]));
                Shutdown(0);
            }
        }
        catch (Exception ex)
        {
            CrashEvidence.Record(ex,"Startup");
            // Startup failure evidence goes only to Studio 2's own root; never to legacy settings.
            var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AhaKey", "Studio2");
            using var failureLog=new SessionLogProvider(new SettingsStore(root));
            failureLog.CreateLogger("Startup").LogError(ex,"Application startup failed");
            if(e.Args.Length==2 && (e.Args[0]=="--smoke-test" || e.Args[0].EndsWith("-smoke",StringComparison.Ordinal)))
            {Directory.CreateDirectory(e.Args[1]);File.WriteAllText(Path.Combine(e.Args[1],"smoke-error.txt"),ex.ToString());Shutdown(2);return;}
            MessageBox.Show("AhaKey Studio could not start. See the per-user Studio2 Logs folder.","AhaKey Studio",MessageBoxButton.OK,MessageBoxImage.Error);
            Shutdown(1);
        }
    }
    protected override void OnExit(ExitEventArgs e)
    {
        if (host is not null) { host.StopAsync(TimeSpan.FromSeconds(3)).GetAwaiter().GetResult(); if(host is IAsyncDisposable asyncHost)asyncHost.DisposeAsync().AsTask().GetAwaiter().GetResult();else host.Dispose(); }
        tray?.Dispose();
        instance?.Dispose();
        base.OnExit(e);
    }
}

using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows;
using AhaKey.Integrations;
using AhaKey.Services;
using AhaKey.Studio.ViewModels;
using Microsoft.Extensions.DependencyInjection;

namespace AhaKey.Studio.Services;

// Explicit acceptance entry points, never invoked from startup. Operator obtains app-specific consent first.
public static class CodexAcceptance
{
    public static IntegrationManager Create() => new(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),new SettingsStore().Root,new HostInspection(),
        new ApprovalService(_=>Task.FromResult(new ApprovalSnapshot(false,false,SwitchEvidence.Unknown))));
    private static readonly JsonSerializerOptions Json=new(){WriteIndented=true,Converters={new JsonStringEnumConverter()}};
    private static string Safe(string path)=>path.Replace(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),"%USERPROFILE%",StringComparison.OrdinalIgnoreCase);
    public static async Task ConfigureAsync(string output,bool remove)
    {
        Directory.CreateDirectory(output);var manager=Create();
        try
        {
            await manager.RefreshAsync();
            var status=manager.Statuses.Single(s=>s.Id==AssistantId.Codex);
            if(status.Installed!=EvidenceState.Yes || status.Compatible!=EvidenceState.Yes)throw new InvalidOperationException("Installed Codex schema is not verified.");
            var plan=manager.Preview(AssistantId.Codex,remove?ConfigurationAction.Remove:ConfigurationAction.Configure);
            var receipt=await manager.ApplyAsync(plan);
            File.WriteAllText(Path.Combine(output,remove?"codex-removal.json":"codex-configuration.json"),JsonSerializer.Serialize(new
            {
                At=DateTimeOffset.UtcNow,Action=plan.Action.ToString(),plan.Schema,Backup=Safe(receipt.BackupDirectory),
                Files=receipt.Files.Select(f=>new{Path=Safe(f.Path),f.BeforeHash,f.AfterHash,f.Purpose}),
                Status=manager.Statuses.Single(s=>s.Id==AssistantId.Codex),HardwareAuto=false,PhysicalCommands=0,TrustModified=false
            },Json));
        }
        finally{manager.Approvals.Dispose();await manager.Server.DisposeAsync();}
    }
    public static async Task RunUiAsync(Window window,IServiceProvider services,string output)
    {
        Directory.CreateDirectory(output);var manager=Create();
        var vm=services.GetRequiredService<IntegrationsViewModel>();vm.UseFixture(manager);
        var shell=services.GetRequiredService<ShellViewModel>();
        var l=services.GetRequiredService<LocalizationService>();var theme=services.GetRequiredService<ThemeService>();
        l.Apply(LanguageChoice.English);theme.Apply(ThemeChoice.Light);
        await manager.RefreshAsync();shell.NavigationSelection=shell.Navigation.Single(n=>n.Value==PageId.Integrations);
        window.Width=1024;window.Height=920;
        var signal=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        manager.Activity.Changed+=()=>signal.TrySetResult();
        try
        {
            if(!manager.Server.Start())throw new InvalidOperationException("Port 8765 unavailable; no fallback.");
            File.WriteAllText(Path.Combine(output,"ready.json"),JsonSerializer.Serialize(new{At=DateTimeOffset.UtcNow,Port=8765,HardwareAuto=false,PhysicalCommands=0}));
            await StudioSmokeTest.Capture(window,output,"installed-applications-before-event");
            await signal.Task.WaitAsync(TimeSpan.FromMinutes(4));
            await Task.Delay(500); // Allow metadata to settle, not a new event or hardware query.
            vm.Selected=vm.Rows.Single(r=>r.Id==AssistantId.Codex);
            await StudioSmokeTest.Capture(window,output,"codex-real-event");
            File.WriteAllText(Path.Combine(output,"real-events.json"),JsonSerializer.Serialize(manager.Activity.History,Json));
            File.WriteAllText(Path.Combine(output,"runtime-result.json"),JsonSerializer.Serialize(new{At=DateTimeOffset.UtcNow,Source="Installed assistant hook clients; no synthetic event injected by capture",Statuses=manager.Statuses,HardwareAuto=false,PhysicalCommands=0},Json));
        }
        finally{manager.Approvals.Dispose();await manager.Server.DisposeAsync();File.WriteAllText(Path.Combine(output,"closed.json"),JsonSerializer.Serialize(new{At=DateTimeOffset.UtcNow,ServiceStopped=!manager.Server.Running}));}
    }
}

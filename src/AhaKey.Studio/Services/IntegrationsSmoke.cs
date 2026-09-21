using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using AhaKey.Integrations;
using AhaKey.Services;
using AhaKey.Studio.ViewModels;
using AhaKey.Studio.Views;
using Microsoft.Extensions.DependencyInjection;

namespace AhaKey.Studio.Services;

public static class IntegrationsSmoke
{
    private sealed class FixtureHost : IHostInspection
    {
        public Task<ApplicationInstallation> FindAsync(AssistantId id,CancellationToken ct)=>Task.FromResult(new ApplicationInstallation(id is AssistantId.Codex or AssistantId.Cursor,id==AssistantId.Codex?"0.155.0-alpha.9.2":id==AssistantId.Cursor?"2.0.0":null,id==AssistantId.Codex?"fixture-codex":null));
        public Task<CodexHookEvidence> InspectCodexAsync(string exe,CodexIntegration adapter,CancellationToken ct)=>Task.FromResult(new CodexHookEvidence(EvidenceState.Yes,EvidenceState.Yes,EvidenceState.Yes));
    }
    public static async Task RunAsync(Window window,IServiceProvider services,string output)
    {
        Directory.CreateDirectory(output); var checks=new List<string>{"OFFLINE FIXTURES ONLY; no assistant config or physical device access"};
        void Check(bool ok,string text){if(!ok){File.WriteAllText(Path.Combine(output,"failed-check.txt"),text);throw new InvalidOperationException(text);}checks.Add(text);File.WriteAllLines(Path.Combine(output,"checks-progress.txt"),checks);}
        var l=services.GetRequiredService<LocalizationService>();var theme=services.GetRequiredService<ThemeService>();
        var vm=services.GetRequiredService<IntegrationsViewModel>();var shell=services.GetRequiredService<ShellViewModel>();
        using var approvals=new ApprovalService(_=>Task.FromResult(new ApprovalSnapshot(true,true,SwitchEvidence.Manual)));
        var manager=new IntegrationManager(Path.Combine(output,"fixture-home"),Path.Combine(output,"fixture-studio"),new FixtureHost(),approvals);
        await manager.ApplyAsync(manager.Preview(AssistantId.Codex,ConfigurationAction.Configure));
        vm.UseFixture(manager);shell.NavigationSelection=shell.Navigation.Single(x=>x.Value==PageId.Integrations);await manager.RefreshAsync();
        Check(vm.Rows.Count==4 && vm.Rows.Single(r=>r.Id==AssistantId.Claude).Status.Installed==EvidenceState.No,"Distinct application installation fixtures");
        Check(vm.Rows.Single(r=>r.Id==AssistantId.Codex).Status.Configured==EvidenceState.Yes,"Codex owned config configured");
        Check(manager.Server.Start(0),"Loopback fixture service starts");
        window.Width=1024;window.Height=920;
        foreach(var language in new[]{LanguageChoice.English,LanguageChoice.Russian,LanguageChoice.Chinese})
        foreach(var mode in new[]{ThemeChoice.Light,ThemeChoice.Dark})
        {l.Apply(language);theme.Apply(mode);vm.Selected=null;await StudioSmokeTest.Capture(window,output,$"integrations-{language}-{mode}-1024-offline");}
        l.Apply(LanguageChoice.English);theme.Apply(ThemeChoice.Light);
        using(var client=new TcpClient())
        {
            await client.ConnectAsync(IPAddress.Loopback,manager.Server.Port);
            await client.GetStream().WriteAsync(Encoding.UTF8.GetBytes("{\"cmd\":\"CodexPostToolUse\"}\n"));
            using var reader=new StreamReader(client.GetStream());Check((await reader.ReadLineAsync())!.Contains("codex"),"Real TCP event through offline fixture server");
        }
        Check(manager.Activity.Get(AssistantId.Codex).NativeEvent=="CodexPostToolUse","Event delivered to runtime state");
        var scroll=Find<ScrollViewer>(window).First(v=>v.Content is Grid);
        window.Height=720;
        var row=vm.Rows.Single(r=>r.Id==AssistantId.Codex);
        var detailsButton=Find<Button>(window).Single(b=>b.CommandParameter is AssistantId id && id==AssistantId.Codex && b.Command==vm.DetailsCommand);
        Check(row.PrimaryAction=="StopService" && row.HasPrimary,"Configured running card exposes direct Stop service");
        Check(vm.Rows.Single(r=>r.Id==AssistantId.Cursor).PrimaryAction=="Install","Installed unconfigured card exposes direct Install");
        Check(!vm.Rows.Single(r=>r.Id==AssistantId.Kimi).HasPrimary,"Unsupported integration has no inapplicable primary action");
        await vm.PrimaryCommand.ExecuteAsync(AssistantId.Cursor);
        Check(vm.Selected?.Id==AssistantId.Cursor && vm.HasPlan && vm.Plan!.Files.Count>0,"Direct Install opens exact review plan without applying configuration");vm.CancelPlanCommand.Execute(null);vm.Selected=null;
        window.UpdateLayout();
        var page=Find<IntegrationsPage>(window).Single();
        foreach(var target in Find<ListBoxItem>(page).Cast<UIElement>().Concat(Find<Button>(page).Where(b=>b.IsVisible)).Concat(Find<TextBlock>(page).Where(b=>b.IsVisible && b.DataContext is IntegrationRow)))
        {
            scroll.ScrollToTop();window.UpdateLayout();
            target.RaiseEvent(new System.Windows.Input.MouseWheelEventArgs(System.Windows.Input.Mouse.PrimaryDevice,0,-120){RoutedEvent=System.Windows.Input.Mouse.PreviewMouseWheelEvent});
            window.UpdateLayout();Check(scroll.VerticalOffset>0,"Wheel reaches page owner over "+target.GetType().Name);
        }
        detailsButton.Focus(); var focused=System.Windows.Input.Keyboard.FocusedElement;
        vm.Update(); await Task.Delay(5200); // Cross the actual periodic refresh tick.
        Check(ReferenceEquals(row,vm.Rows.Single(r=>r.Id==AssistantId.Codex)),"Row identity survives periodic refresh");
        Check(ReferenceEquals(focused,System.Windows.Input.Keyboard.FocusedElement),"Keyboard focus survives periodic refresh");
        void Invoke(Button button) => ((System.Windows.Automation.Provider.IInvokeProvider)new System.Windows.Automation.Peers.ButtonAutomationPeer(button).GetPattern(System.Windows.Automation.Peers.PatternInterface.Invoke)).Invoke();
        Invoke(detailsButton);
        await window.Dispatcher.InvokeAsync(()=>{},System.Windows.Threading.DispatcherPriority.ApplicationIdle);
        var back=Find<Button>(window).Single(b=>b.Name=="DetailsBack");
        Check(vm.Selected==row && back.IsKeyboardFocused && scroll.VerticalOffset>0,"Details action reveals and focuses details at 1024x720 DIP");
        window.UpdateLayout();
        bool VisibleInScroll(FrameworkElement element)
        {
            var point=element.TransformToAncestor(scroll).Transform(new Point());
            return point.Y>=0 && point.Y+element.ActualHeight<=scroll.ActualHeight;
        }
        Check(VisibleInScroll(Find<TextBox>(window).Single(b=>b.Name=="DetailsConfigPath")) && VisibleInScroll(Find<Button>(window).Single(b=>b.Name=="DetailsInstall")),"Details config path and first action are fully inside viewport");
        await StudioSmokeTest.Capture(window,output,"codex-details-offline");
        scroll.ScrollToTop();window.UpdateLayout();
        Find<TextBox>(window).Single(b=>b.Name=="DetailsConfigPath").RaiseEvent(new System.Windows.Input.MouseWheelEventArgs(System.Windows.Input.Mouse.PrimaryDevice,0,-120){RoutedEvent=System.Windows.Input.Mouse.PreviewMouseWheelEvent});
        window.UpdateLayout();Check(scroll.VerticalOffset>0,"Wheel over details summary scrolls page");
        vm.PrepareCommand.Execute("Repair");Check(vm.HasPlan && !vm.CanApply && vm.Plan!.Files.Count==0,"Unchanged repair has explicit no-op preview and disabled Apply");
        vm.CancelPlanCommand.Execute(null);
        vm.PrepareCommand.Execute("Remove");Check(vm.Plan!.HookChanges.Count==6 && vm.PlanText.Contains("CodexPreToolUse") && !vm.PlanText.Contains(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)),"Preview shows six owned commands with sanitized paths");
        scroll.ScrollToEnd();await StudioSmokeTest.Capture(window,output,"owned-changes-preview-offline");
        vm.CancelPlanCommand.Execute(null);Check(!vm.HasPlan,"Preview cancellation leaves configuration alone");
        Invoke(back);await window.Dispatcher.InvokeAsync(()=>{},System.Windows.Threading.DispatcherPriority.ApplicationIdle);
        Check(vm.Selected is null && detailsButton.IsKeyboardFocused,"Closing details returns focus to its initiating button");
        window.Height=920;vm.Selected=row;
        Find<Expander>(window).Single(e=>System.Windows.Automation.AutomationProperties.GetAutomationId(e)=="IntegrationEvents").IsExpanded=true;
        scroll.ScrollToEnd();await StudioSmokeTest.Capture(window,output,"event-received-offline");
        IntegrationApprovalWindow? dialog=null;
        approvals.PendingChanged+=r=>window.Dispatcher.BeginInvoke(()=>{dialog?.Close();dialog=null;if(r is not null && !r.Decision.IsCompleted){dialog=new(r,l){Owner=window};dialog.Show();}});
        var pending=approvals.DecideAsync(HookContract.Events["PermissionRequest"],default);
        await window.Dispatcher.InvokeAsync(()=>{},System.Windows.Threading.DispatcherPriority.ApplicationIdle);
        Check(dialog is not null,"Non-blocking manual approval dialog shown");
        await StudioSmokeTest.Capture(dialog!,output,"manual-approval-offline");approvals.Pending!.Resolve(false);
        Check((await pending).Outcome=="denied","Manual denial distinguished from unavailable hardware");
        await manager.Server.DisposeAsync();using var collision=new TcpListener(IPAddress.Loopback,0);collision.Start();
        Check(!manager.Server.Start(((IPEndPoint)collision.LocalEndpoint).Port),"Port collision fails without fallback");
        vm.Selected=null;scroll.ScrollToTop();await StudioSmokeTest.Capture(window,output,"port-collision-offline");
        await manager.Server.DisposeAsync();
        Check(services.GetRequiredService<AhaKey.Device.DeviceManager>().Device.Status.SessionId is null,"No physical or Mock device session opened");
        File.WriteAllLines(Path.Combine(output,"checks.txt"),checks);
    }
    private static IEnumerable<T> Find<T>(DependencyObject root) where T:DependencyObject
    {
        if(root is T value)yield return value;
        for(int i=0;i<System.Windows.Media.VisualTreeHelper.GetChildrenCount(root);i++)
            foreach(var child in Find<T>(System.Windows.Media.VisualTreeHelper.GetChild(root,i)))yield return child;
    }
    public static async Task InspectHostAsync(string output)
    {
        Directory.CreateDirectory(output);
        using var approvals=new ApprovalService(_=>Task.FromResult(new ApprovalSnapshot(false,false,SwitchEvidence.Unknown)));
        var root=new SettingsStore().Root;
        var manager=new IntegrationManager(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),root,new HostInspection(),approvals);
        await manager.RefreshAsync();
        var json=new JsonSerializerOptions{WriteIndented=true,Converters={new System.Text.Json.Serialization.JsonStringEnumConverter()}};
        File.WriteAllText(Path.Combine(output,"host-inspection.json"),JsonSerializer.Serialize(manager.Statuses,json));
        foreach(var status in manager.Statuses.Where(s=>s.Installed==EvidenceState.Yes && s.Compatible==EvidenceState.Yes))
        {
            var plan=manager.Preview(status.Id,ConfigurationAction.Configure);
            File.WriteAllText(Path.Combine(output,status.Id+"-preview.json"),JsonSerializer.Serialize(new{Integration=status.Id.ToString(),plan.Schema,Files=plan.Files.Select(f=>new{Path=f.Path.Replace(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),"%USERPROFILE%"),f.BeforeHash,f.AfterHash,f.Purpose}),OwnedCommands=manager.Adapters.Single(a=>a.Id==status.Id).Events.Select(e=>manager.Adapters.Single(a=>a.Id==status.Id).Command(e).Replace(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),"%USERPROFILE%")),ExistingEntries="Preserved; legacy hooks are not adopted or removed",Trust="Not modified; native application manages trust"},json));
        }
    }
}

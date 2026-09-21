using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using AhaKey.Integrations;

namespace AhaKey.Integrations.Tests;

public sealed class IntegrationTests : IDisposable
{
    private readonly string root = Path.Combine(Path.GetTempPath(), "ahakey-integration-tests", Guid.NewGuid().ToString("N"));
    private AssistantIntegration Adapter(AssistantId id) => id switch
    {
        AssistantId.Claude => new ClaudeIntegration(root, Path.Combine(root, "scripts")),
        AssistantId.Cursor => new CursorIntegration(root, Path.Combine(root, "scripts")),
        _ => new CodexIntegration(root, Path.Combine(root, "scripts"))
    };
    private void Save(AssistantIntegration adapter, string json) { Directory.CreateDirectory(Path.GetDirectoryName(adapter.ConfigPath)!); File.WriteAllText(adapter.ConfigPath, json); }
    [Theory]
    [InlineData(AssistantId.Claude)] [InlineData(AssistantId.Cursor)] [InlineData(AssistantId.Codex)]
    public async Task ConfigureRepairRemovePreserveUnrelatedSettings(AssistantId id)
    {
        var a = Adapter(id); Save(a, "{\"custom\":{\"secret\":\"retain locally\"},\"hooks\":{}}");
        var writer = new OwnedConfiguration(Path.Combine(root, "backups"));
        var receipt = await writer.ApplyAsync(a.Preview(ConfigurationAction.Install));
        Assert.True(a.Inspect().Configured); Assert.True(File.Exists(Path.Combine(receipt.BackupDirectory, "manifest.json")));
        await writer.ApplyAsync(a.Preview(ConfigurationAction.Repair));
        var configured = SafeJson.Parse(File.ReadAllBytes(a.ConfigPath));
        foreach (var ev in configured["hooks"]!.AsObject()) Assert.Single(ev.Value!.AsArray());
        configured["newerUserSetting"] = 42; File.WriteAllBytes(a.ConfigPath, SafeJson.Encode(configured));
        await writer.ApplyAsync(a.Preview(ConfigurationAction.Remove));
        var removed = SafeJson.Parse(File.ReadAllBytes(a.ConfigPath));
        Assert.Equal(42, removed["newerUserSetting"]!.GetValue<int>());
        Assert.Equal("retain locally", removed["custom"]!["secret"]!.GetValue<string>());
        Assert.False(a.Inspect().Configured);
    }
    [Theory]
    [InlineData("{")] [InlineData("{\"hooks\":[]}")] [InlineData("{\"version\":99}")]
    [InlineData("{\"hooks\":{},\"hooks\":{}}")]
    [InlineData("{\"hooks\":{\"SessionStart\":{}}}")]
    public void BadOrUnknownConfigNeverOverwritten(string input)
    {
        var a = Adapter(AssistantId.Codex); Save(a, input);
        Assert.ThrowsAny<Exception>(() => a.Preview(ConfigurationAction.Configure));
        Assert.Equal(input, File.ReadAllText(a.ConfigPath));
    }
    [Fact] public async Task ConcurrentUserEditInvalidatesPreview()
    {
        var a = Adapter(AssistantId.Claude); Save(a, "{}"); var plan = a.Preview(ConfigurationAction.Configure);
        File.WriteAllText(a.ConfigPath, "{\"new\":true}");
        await Assert.ThrowsAsync<IOException>(() => new OwnedConfiguration(Path.Combine(root, "backups")).ApplyAsync(plan));
        Assert.Equal("{\"new\":true}", File.ReadAllText(a.ConfigPath)); Assert.False(File.Exists(a.ScriptPath));
    }
    [Fact] public async Task AtomicFailureRollsBackOwnScriptAndRetainsOriginal()
    {
        var a = Adapter(AssistantId.Claude); Save(a, "{}");
        var writer = new OwnedConfiguration(Path.Combine(root, "backups")) { BeforeReplace = p => { if (p == a.ConfigPath) throw new IOException(); } };
        await Assert.ThrowsAsync<IOException>(() => writer.ApplyAsync(a.Preview(ConfigurationAction.Install)));
        Assert.Equal("{}", File.ReadAllText(a.ConfigPath)); Assert.False(File.Exists(a.ScriptPath));
    }
    [Fact] public async Task MixedWrapperKeepsUnrelatedCommand()
    {
        var a = Adapter(AssistantId.Codex); var writer = new OwnedConfiguration(Path.Combine(root, "backups"));
        await writer.ApplyAsync(a.Preview(ConfigurationAction.Configure));
        var json = SafeJson.Parse(File.ReadAllBytes(a.ConfigPath));
        json["hooks"]!["PreToolUse"]![0]!["hooks"]!.AsArray().Add(new System.Text.Json.Nodes.JsonObject { ["type"]="command", ["command"]="echo user-owned" });
        File.WriteAllBytes(a.ConfigPath, SafeJson.Encode(json));
        await writer.ApplyAsync(a.Preview(ConfigurationAction.Remove));
        Assert.Contains("echo user-owned", File.ReadAllText(a.ConfigPath));
    }
    [Theory]
    [InlineData(false, false, SwitchEvidence.Auto)] [InlineData(true, false, SwitchEvidence.Auto)]
    [InlineData(true, true, SwitchEvidence.Unknown)]
    public async Task StaleDisconnectedUnknownFailClosed(bool connected, bool fresh, SwitchEvidence mode)
    {
        using var service = new ApprovalService(_ => Task.FromResult(new ApprovalSnapshot(connected, fresh, mode))) { HardwareAutoEnabled = true };
        var decision = await service.DecideAsync(HookContract.Events["CodexPreToolUse"], default);
        Assert.False(decision.Allow); Assert.Equal("codex-fallback", decision.Source);
    }
    [Fact] public async Task FreshAutoRequiresExplicitOptIn()
    {
        using var service = new ApprovalService(_ => Task.FromResult(new ApprovalSnapshot(true, true, SwitchEvidence.Auto)));
        Assert.False((await service.DecideAsync(HookContract.Events["CodexPreToolUse"], default)).Allow);
        service.HardwareAutoEnabled = true;
        Assert.Equal("hardware-auto", (await service.DecideAsync(HookContract.Events["CodexPreToolUse"], default)).Source);
    }
    [Theory] [InlineData(true)] [InlineData(false)]
    public async Task ManualAllowAndDenialAreExplicit(bool allow)
    {
        using var service = new ApprovalService(_ => Task.FromResult(new ApprovalSnapshot(true, true, SwitchEvidence.Manual)));
        service.PendingChanged += r => r?.Resolve(allow);
        var decision = await service.DecideAsync(HookContract.Events["CodexPreToolUse"], default);
        Assert.Equal(allow, decision.Allow); Assert.Equal(allow ? "allowed" : "denied", decision.Outcome);
    }
    [Fact] public async Task ManualTimeoutAndConcurrentBusyAndClose()
    {
        using var service = new ApprovalService(_ => Task.FromResult(new ApprovalSnapshot(true, true, SwitchEvidence.Manual))) { ManualTimeout=TimeSpan.FromMilliseconds(50) };
        service.PendingChanged += _ => { };
        var first = service.DecideAsync(HookContract.Events["CodexPreToolUse"], default);
        Assert.Equal("busy", (await service.DecideAsync(HookContract.Events["CodexPreToolUse"], default)).Outcome);
        Assert.Equal("timeout", (await first).Outcome);
        var pending = service.DecideAsync(HookContract.Events["CodexPreToolUse"], default); service.Dispose();
        Assert.False((await pending).Allow);
    }
    [Theory] [InlineData("{bad}")] [InlineData("{\"cmd\":\"Stop\",\"cmd\":\"PreToolUse\"}")]
    [InlineData("{\"cmd\":\"Stop\",\"prompt\":\"secret\"}")] [InlineData("UnknownEvent")]
    public void StrictMessagesRejectMalformedAndUnknown(string text) => Assert.ThrowsAny<Exception>(() => HookDispatchServer.Parse(text));
    [Fact] public void NineEventsAreSeparateFromPresentationStatesAndHistoryBounded()
    {
        Assert.Equal(9, Enum.GetValues<IdeEvent>().Length); var activity = new TaskActivityService();
        for(int i=0;i<130;i++) activity.Accept(HookDispatchServer.Parse("{\"cmd\":\"Stop\",\"title\":\"private\"}"));
        Assert.Equal(100,activity.History.Count); Assert.DoesNotContain("private",JsonSerializer.Serialize(activity.History));
    }
    [Fact] public async Task LoopbackCollisionMalformedOversizeTimeoutConcurrencyAndTeardown()
    {
        using var approvals = new ApprovalService(_=>Task.FromResult(new ApprovalSnapshot(false,false,SwitchEvidence.Unknown)));
        var activity=new TaskActivityService();await using var server=new HookDispatchServer(activity,approvals){ReadTimeout=TimeSpan.FromMilliseconds(100)};
        Assert.True(server.Start(0)); int port=server.Port;
        await using var collision=new HookDispatchServer(activity,approvals);Assert.False(collision.Start(port));Assert.Equal("IntegrationPortCollision",collision.ErrorKey);
        async Task<string> Send(string text)
        {
            using var client=new TcpClient();await client.ConnectAsync(IPAddress.Loopback,port);
            await client.GetStream().WriteAsync(Encoding.UTF8.GetBytes(text));
            using var reader=new StreamReader(client.GetStream());return await reader.ReadLineAsync().WaitAsync(TimeSpan.FromSeconds(3)) ?? "";
        }
        Assert.Contains("invalid-or-timeout",await Send("{bad}\n"));
        Assert.Contains("invalid-or-timeout",await Send(new string('x',4096)));
        Assert.Contains("invalid-or-timeout",await Send("S"));
        var replies=await Task.WhenAll(Enumerable.Range(0,4).Select(_=>Send("CodexSessionStart\n")));
        Assert.All(replies,r=>Assert.Contains("codex",r)); Assert.Equal(4,activity.History.Count);
        await server.DisposeAsync(); Assert.False(server.Running);
        using var listener=new TcpListener(IPAddress.Loopback,port);listener.Start();
    }
    [Fact] public void KimiIsBlocked() => Assert.Throws<InvalidOperationException>(()=>new KimiIntegration(root,root).Preview(ConfigurationAction.Install));
    [Fact] public async Task ConfiguredDoesNotMeanEnabled()
    {
        var a=Adapter(AssistantId.Claude);Save(a,"{\"disableAllHooks\":true}");
        await new OwnedConfiguration(Path.Combine(root,"backups")).ApplyAsync(a.Preview(ConfigurationAction.Install));
        Assert.True(a.Inspect().Configured);Assert.Equal(EvidenceState.No,a.EnabledState);
    }
    private sealed class MissingHost : IHostInspection
    {
        public Task<ApplicationInstallation> FindAsync(AssistantId id,CancellationToken ct)=>Task.FromResult(new ApplicationInstallation(false,null,null));
        public Task<CodexHookEvidence> InspectCodexAsync(string exe,CodexIntegration a,CancellationToken ct)=>throw new InvalidOperationException();
    }
    [Fact] public async Task MissingApplicationAndUnknownVersionStayDistinctFromConfig()
    {
        using var approvals=new ApprovalService(_=>Task.FromResult(new ApprovalSnapshot(false,false,SwitchEvidence.Unknown)));
        var manager=new IntegrationManager(root,Path.Combine(root,"studio"),new MissingHost(),approvals);
        await manager.ApplyAsync(manager.Preview(AssistantId.Codex,ConfigurationAction.Configure));
        var status=manager.Statuses.Single(s=>s.Id==AssistantId.Codex);
        Assert.Equal(EvidenceState.No,status.Installed);Assert.Equal(EvidenceState.Yes,status.Configured);Assert.Equal(EvidenceState.Unknown,status.Compatible);Assert.Equal(EvidenceState.Unknown,status.Trusted);
        Assert.False(status.ServiceRunning);Assert.Null(status.LastActivity);
    }
    [Fact] public void RemovingMissingConfigIsNoOp() => Assert.Empty(Adapter(AssistantId.Codex).Preview(ConfigurationAction.Remove).Files);
    [Fact] public async Task PreviewNamesOnlyOwnedHookChangesAndDetectsNoOp()
    {
        var a = Adapter(AssistantId.Codex); Save(a,"{\"privateToken\":\"do-not-display\"}");
        var writer = new OwnedConfiguration(Path.Combine(root,"backups"));
        var plan = a.Preview(ConfigurationAction.Install);
        Assert.Equal(6, plan.HookChanges.Count);
        Assert.All(plan.HookChanges, c => { Assert.Equal(0,c.BeforeCount); Assert.Equal(1,c.AfterCount); Assert.Contains("ahakey-studio2-codex",c.Command); });
        Assert.DoesNotContain("do-not-display",JsonSerializer.Serialize(plan.HookChanges));
        await writer.ApplyAsync(plan);
        Assert.Empty(a.Preview(ConfigurationAction.Repair).Files);
        Assert.Empty(a.Preview(ConfigurationAction.Repair).HookChanges);
        Assert.All(a.Preview(ConfigurationAction.Remove).HookChanges,c => { Assert.Equal(1,c.BeforeCount); Assert.Equal(0,c.AfterCount); });
    }
    [Fact] public async Task ConcurrentShutdownIsJoinedBeforeRestart()
    {
        using var approvals = new ApprovalService(_=>Task.FromResult(new ApprovalSnapshot(false,false,SwitchEvidence.Unknown)));
        await using var server = new HookDispatchServer(new TaskActivityService(),approvals);
        Assert.True(server.Start(0));
        using var client = new TcpClient(); await client.ConnectAsync(IPAddress.Loopback,server.Port);
        await client.GetStream().WriteAsync("S"u8.ToArray());
        var stop = server.DisposeAsync().AsTask();
        if (!stop.IsCompleted) Assert.False(server.Start(0));
        await Task.WhenAll(stop,server.DisposeAsync().AsTask()).WaitAsync(TimeSpan.FromSeconds(3));
        Assert.True(server.Start(0)); Assert.True(server.Running);
    }
    public void Dispose() { if(Directory.Exists(root)) Directory.Delete(root,true); }
}

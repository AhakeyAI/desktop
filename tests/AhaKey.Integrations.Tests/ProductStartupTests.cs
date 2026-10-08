using AhaKey.Integrations;

namespace AhaKey.Integrations.Tests;
public sealed class ProductStartupTests:IDisposable
{
    private readonly string root=Path.Combine(Path.GetTempPath(),"ahakey-product-integration",Guid.NewGuid().ToString("N"));
    private sealed class Host(bool trusted):IHostInspection
    {
        public Task<ApplicationInstallation> FindAsync(AssistantId id,CancellationToken ct)=>Task.FromResult(new ApplicationInstallation(id==AssistantId.Codex,"0.155.0","fixture"));
        public Task<CodexHookEvidence> InspectCodexAsync(string exe,CodexIntegration adapter,CancellationToken ct)=>Task.FromResult(new CodexHookEvidence(EvidenceState.Yes,trusted?EvidenceState.Yes:EvidenceState.No,EvidenceState.Yes));
    }
    [Theory][InlineData(false,true,true,false)][InlineData(true,false,true,false)][InlineData(true,true,false,false)][InlineData(true,true,true,true)]
    public async Task StartupRequiresOptInConfigurationAndTrustAndNeverMutatesHooks(bool optedIn,bool configured,bool trusted,bool starts)
    {
        using var approvals=new ApprovalService(_=>Task.FromResult(new ApprovalSnapshot(false,false,SwitchEvidence.Unknown)));
        var manager=new IntegrationManager(root,Path.Combine(root,"studio"),new Host(trusted),approvals);
        var adapter=manager.Adapters.Single(a=>a.Id==AssistantId.Codex);
        if(configured)await manager.ApplyAsync(manager.Preview(AssistantId.Codex,ConfigurationAction.Install));
        var before=File.Exists(adapter.ConfigPath)?File.ReadAllText(adapter.ConfigPath):null;
        Assert.Equal(starts,await IntegrationStartup.InitializeAsync(manager,optedIn,0));Assert.Equal(starts,manager.Server.Running);
        Assert.Equal(before,File.Exists(adapter.ConfigPath)?File.ReadAllText(adapter.ConfigPath):null);
        await manager.Server.DisposeAsync();
    }
    [Fact] public void UnknownTrustCannotBecomeReadyFromServiceOrActivity()
    {
        var status=new IntegrationStatus(AssistantId.Codex,EvidenceState.Yes,"1",EvidenceState.Yes,EvidenceState.Yes,EvidenceState.Unknown,EvidenceState.Yes,true,DateTimeOffset.UtcNow,null,"fixture");
        Assert.False(status.Ready);Assert.True((status with{Trusted=EvidenceState.Yes}).Ready);
    }
    [Fact] public void DesktopCodexIsFoundWithoutInheritedPathButExplicitPathWins()
    {
        var bin=Path.Combine(root,"OpenAI","Codex","bin","installed-build");Directory.CreateDirectory(bin);
        var desktop=Path.Combine(bin,"codex.exe");File.WriteAllText(desktop,"");
        Assert.Equal(desktop,HostInspection.ResolveExecutable(AssistantId.Codex,[],root));
        Assert.Null(HostInspection.ResolveExecutable(AssistantId.Cursor,[],root));
        var cli=Path.Combine(root,"cli");Directory.CreateDirectory(cli);var exe=Path.Combine(cli,"codex.exe");File.WriteAllText(exe,"");
        Assert.Equal(exe,HostInspection.ResolveExecutable(AssistantId.Codex,[cli],root));
    }
    public void Dispose(){if(Directory.Exists(root))Directory.Delete(root,true);}
}

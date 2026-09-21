namespace AhaKey.Integrations;

public sealed class IntegrationManager
{
    private readonly IHostInspection host;
    private readonly OwnedConfiguration files;
    private readonly SemaphoreSlim refresh = new(1, 1);
    private IReadOnlyList<IntegrationStatus> statuses = [];
    public IReadOnlyList<AssistantIntegration> Adapters { get; }
    public TaskActivityService Activity { get; }
    public ApprovalService Approvals { get; }
    public HookDispatchServer Server { get; }
    public IReadOnlyList<IntegrationStatus> Statuses => statuses.Select(s => s with { ServiceRunning = Server.Running, LastActivity = Activity.Get(s.Id).LastActivity }).ToArray();
    public event Action? Changed;
    public IntegrationManager(string home, string root, IHostInspection host, ApprovalService approvals)
    {
        this.host = host; files = new(Path.Combine(root, "integration-backups"));
        string scripts = Path.Combine(root, "integration-hooks");
        Adapters = [new ClaudeIntegration(home, scripts), new CursorIntegration(home, scripts), new CodexIntegration(home, scripts), new KimiIntegration(home, scripts)];
        Activity = new(); Approvals = approvals; Server = new(Activity, approvals);
        Activity.Changed += () => Changed?.Invoke(); Server.Changed += () => Changed?.Invoke();
    }
    public async Task RefreshAsync(CancellationToken ct = default)
    {
        await refresh.WaitAsync(ct);
        try
        {
            var result = new List<IntegrationStatus>();
            foreach (var adapter in Adapters)
            {
                var installed = await host.FindAsync(adapter.Id, ct);
                var (configured, compatible) = adapter.Inspect();
                if(adapter is CodexIntegration known && known.RecognizedCommands.Count==known.Events.Count())configured=true;
                var compatibility = !adapter.Supported || !compatible ? EvidenceState.No : installed.Version is null ? EvidenceState.Unknown : EvidenceState.Yes;
                var enabled = adapter.EnabledState;
                var trusted = adapter.Id == AssistantId.Codex ? EvidenceState.Unknown : EvidenceState.NotRequired;
                if (adapter is CodexIntegration codex && installed.Executable is {} exe)
                {
                    var live = await host.InspectCodexAsync(exe, codex, ct);
                    compatibility = compatible ? live.Compatible : EvidenceState.No; enabled = live.Enabled; trusted = live.Trusted;
                }
                result.Add(new(adapter.Id, installed.Installed ? EvidenceState.Yes : EvidenceState.No, installed.Version,
                    configured ? EvidenceState.Yes : EvidenceState.No, enabled, trusted, compatibility, Server.Running,
                    Activity.Get(adapter.Id).LastActivity, !compatible ? adapter.Supported ? "IntegrationUnsafeConfig" : "IntegrationKimiBlocked" : null, adapter.SanitizedPath));
            }
            statuses = result;
        }
        finally { refresh.Release(); Changed?.Invoke(); }
    }
    public ConfigurationPlan Preview(AssistantId id, ConfigurationAction action) => Adapters.Single(a => a.Id == id).Preview(action);
    public async Task<ConfigurationReceipt> ApplyAsync(ConfigurationPlan plan, CancellationToken ct = default)
    {
        var receipt = await files.ApplyAsync(plan, ct); await RefreshAsync(ct); return receipt;
    }
}

namespace AhaKey.Integrations;

public enum SwitchEvidence { Unknown, Auto, Manual }
public sealed record ApprovalSnapshot(bool Connected, bool Fresh, SwitchEvidence Switch);
public sealed record ApprovalDecision(bool Allow, string Source, string Outcome);
public sealed class ManualApprovalRequest(HookEvent context)
{
    private readonly TaskCompletionSource<bool> completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
    public Guid Id { get; } = Guid.NewGuid();
    public HookEvent Context { get; } = context;
    public Task<bool> Decision => completion.Task;
    public bool Resolve(bool allow) => completion.TrySetResult(allow);
}

public sealed class ApprovalService(Func<CancellationToken, Task<ApprovalSnapshot>> statusSource) : IDisposable
{
    private readonly SemaphoreSlim active = new(1, 1);
    private readonly CancellationTokenSource lifetime = new();
    public bool HardwareAutoEnabled { get; set; } // Explicit session opt-in, never enabled by startup or telemetry.
    public TimeSpan ManualTimeout { get; init; } = TimeSpan.FromSeconds(15);
    public TimeSpan QueryTimeout { get; init; } = TimeSpan.FromMilliseconds(500);
    public event Action<ManualApprovalRequest?>? PendingChanged;
    public ManualApprovalRequest? Pending { get; private set; }

    public async Task<ApprovalDecision> DecideAsync(HookEvent ev, CancellationToken ct)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(ct, lifetime.Token);
        if (!await active.WaitAsync(0, linked.Token)) return new(false, "fail-closed", "busy");
        try
        {
            ApprovalSnapshot snapshot;
            using (var query = CancellationTokenSource.CreateLinkedTokenSource(linked.Token))
            {
                query.CancelAfter(QueryTimeout);
                try { snapshot = await statusSource(query.Token).WaitAsync(query.Token); }
                catch (Exception ex) when (ex is not OutOfMemoryException) { snapshot = new(false, false, SwitchEvidence.Unknown); }
            }
            if (snapshot.Connected && snapshot.Fresh && snapshot.Switch == SwitchEvidence.Auto && HardwareAutoEnabled)
                return new(true, "hardware-auto", "allowed");
            // Codex preserves native fallback when fresh physical MANUAL evidence is unavailable.
            if (ev.Integration == AssistantId.Codex && !(snapshot.Connected && snapshot.Fresh && snapshot.Switch == SwitchEvidence.Manual))
                return new(false, "codex-fallback", "unavailable");
            if (PendingChanged is null) return new(false, "fail-closed", "unavailable");
            Pending = new(ev);
            PendingChanged.Invoke(Pending);
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(linked.Token);
            timeout.CancelAfter(ManualTimeout);
            try
            {
                bool allow = await Pending.Decision.WaitAsync(timeout.Token);
                return new(allow, allow ? "user-confirmed" : "fail-closed", allow ? "allowed" : "denied");
            }
            catch (OperationCanceledException) { Pending.Resolve(false); return new(false, "fail-closed", linked.IsCancellationRequested ? "cancelled" : "timeout"); }
        }
        finally { Pending = null; PendingChanged?.Invoke(null); active.Release(); }
    }
    public void Dispose() { lifetime.Cancel(); }
}

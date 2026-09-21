namespace AhaKey.Integrations;

public enum AssistantId { Claude, Cursor, Codex, Kimi }
public enum EvidenceState { Yes, No, Unknown, NotRequired }
public enum IdeEvent { Notification, PermissionRequest, PostToolUse, PreToolUse, SessionStart, Stop, TaskCompleted, UserPromptSubmit, SessionEnd }
public enum ActivityState { Idle, SessionActive, Working, WaitingForPermission, ToolExecuting, Completed, Stopped, Error }
public sealed record IntegrationStatus(AssistantId Id, EvidenceState Installed, string? Version,
    EvidenceState Configured, EvidenceState Enabled, EvidenceState Trusted, EvidenceState Compatible,
    bool ServiceRunning, DateTimeOffset? LastActivity, string? LastError, string ConfigPath)
{
    public bool Ready => Installed == EvidenceState.Yes && Configured == EvidenceState.Yes && Enabled == EvidenceState.Yes &&
        Trusted is EvidenceState.Yes or EvidenceState.NotRequired && Compatible == EvidenceState.Yes;
}
public sealed record HookEvent(AssistantId Integration, IdeEvent Event, string NativeEvent)
{public string? TaskId {get;init;}public string? EventId {get;init;}public string? Outcome {get;init;}}
public sealed record ActivityEntry(DateTimeOffset At, AssistantId Integration, IdeEvent Event,
    string NativeEvent, string Result, string? ApprovalSource);
public sealed record RuntimeState(ActivityState State, DateTimeOffset? LastActivity, string? NativeEvent);

public static class HookContract
{
    public const int Port = 8765;
    public static readonly IReadOnlyDictionary<string, HookEvent> Events = Build();
    private static Dictionary<string, HookEvent> Build()
    {
        var result = new Dictionary<string, HookEvent>(StringComparer.Ordinal);
        void Add(AssistantId id, string native, IdeEvent ev) => result.Add(native, new(id, ev, native));
        foreach (var ev in Enum.GetValues<IdeEvent>()) Add(AssistantId.Claude, ev.ToString(), ev);
        foreach (var ev in new[] { IdeEvent.SessionStart, IdeEvent.SessionEnd, IdeEvent.PreToolUse, IdeEvent.PostToolUse, IdeEvent.Stop, IdeEvent.UserPromptSubmit, IdeEvent.PermissionRequest })
            Add(AssistantId.Codex, "Codex" + ev, ev);
        foreach (var ev in new[] { IdeEvent.SessionStart, IdeEvent.SessionEnd, IdeEvent.PreToolUse, IdeEvent.PostToolUse, IdeEvent.Stop })
            Add(AssistantId.Cursor, char.ToLowerInvariant(ev.ToString()[0]) + ev.ToString()[1..], ev);
        // Kimi intentionally disabled: retained installer writes TOML blocks to hooks.json and depends on a CLI patch.
        return result;
    }
    public static bool RequiresApproval(HookEvent ev) => ev.Event == IdeEvent.PermissionRequest ||
        ev.Event == IdeEvent.PreToolUse && ev.Integration is AssistantId.Codex or AssistantId.Cursor;
}

public sealed class TaskActivityService
{
    private readonly object sync = new();
    private readonly Queue<ActivityEntry> history = new();
    private readonly Dictionary<AssistantId, RuntimeState> states = new();
    public event Action? Changed;
    public IReadOnlyList<ActivityEntry> History { get { lock (sync) return history.Reverse().ToArray(); } }
    public RuntimeState Get(AssistantId id) { lock (sync) return states.GetValueOrDefault(id, new(ActivityState.Idle, null, null)); }
    public void Accept(HookEvent ev, string result = "received", string? source = null)
    {
        var now = DateTimeOffset.UtcNow;
        var state = ev.Event switch
        {
            IdeEvent.SessionStart => ActivityState.SessionActive,
            IdeEvent.UserPromptSubmit or IdeEvent.PostToolUse => ActivityState.Working,
            IdeEvent.PermissionRequest => ActivityState.WaitingForPermission,
            IdeEvent.PreToolUse => ActivityState.ToolExecuting,
            IdeEvent.TaskCompleted => ActivityState.Completed,
            IdeEvent.Stop => ActivityState.Stopped,
            IdeEvent.SessionEnd => ActivityState.Idle,
            _ => Get(ev.Integration).State
        };
        if (result == "pending") state = ActivityState.WaitingForPermission;
        if (result == "denied") state = ActivityState.Stopped;
        if (result is "unavailable" or "timeout" or "busy") state = ActivityState.Error;
        lock (sync)
        {
            states[ev.Integration] = new(state, now, ev.NativeEvent);
            history.Enqueue(new(now, ev.Integration, ev.Event, ev.NativeEvent, result, source));
            while (history.Count > 100) history.Dequeue();
        }
        Changed?.Invoke();
    }
}

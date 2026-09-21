namespace AhaKey.Integrations;

public enum AssistantProductState { Idle, Done, Working, NeedsAttention, Error }
public sealed record AssistantTaskState(AssistantId Integration,string Ownership,AssistantProductState State,
    DateTimeOffset LastEventAt,TimeSpan Ttl,long Sequence)
{public DateTimeOffset ExpiresAt=>LastEventAt+Ttl; public int Priority=>(int)State;}
public sealed record AssistantAggregate(AssistantProductState State,AssistantTaskState? Owner,int ActiveTasks,long Generation);
// Metadata only. No prompt/tool text. Completion clears its own task, never a different owner.
public sealed class AssistantRuntimeCoordinator(TimeProvider? timeProvider=null)
{
    private readonly TimeProvider clock=timeProvider??TimeProvider.System;
    private readonly object sync=new();
    private readonly Dictionary<(AssistantId,string),AssistantTaskState> tasks=[];
    private readonly Dictionary<(AssistantId,string,string),DateTimeOffset> duplicateEvents=[];
    private long sequence,generation;
    public long Generation {get{lock(sync)return generation;}}
    public TimeSpan ActiveTtl {get;init;}=TimeSpan.FromMinutes(5);
    public TimeSpan DoneTtl {get;init;}=TimeSpan.FromSeconds(3);
    public IReadOnlyList<AssistantTaskState> Sessions {get{lock(sync){Expire();return tasks.Values.ToArray();}}}
    public bool Accept(HookEvent ev)
    {
        lock(sync)
        {
            Expire();var now=clock.GetUtcNow();string owner=ev.TaskId??"unidentified";
            var eventKey=(ev.Integration,owner,ev.EventId??ev.NativeEvent);
            if(duplicateEvents.TryGetValue(eventKey,out var seen)&&now-seen<(ev.EventId is null?TimeSpan.FromMilliseconds(250):TimeSpan.FromMinutes(5)))return false;
            duplicateEvents[eventKey]=now;
            if(duplicateEvents.Count>1024)duplicateEvents.Remove(duplicateEvents.MinBy(x=>x.Value).Key);
            var key=(ev.Integration,owner);
            var state=ev.Event switch
            {
                IdeEvent.PreToolUse or IdeEvent.PostToolUse or IdeEvent.UserPromptSubmit or IdeEvent.SessionStart=>AssistantProductState.Working,
                IdeEvent.PermissionRequest=>AssistantProductState.NeedsAttention,
                IdeEvent.TaskCompleted or IdeEvent.Stop=>AssistantProductState.Done,
                IdeEvent.SessionEnd=>AssistantProductState.Idle,
                _=>tasks.GetValueOrDefault(key)?.State??AssistantProductState.Idle
            };
            if(ev.Outcome=="error")state=AssistantProductState.Error;
            if(state==AssistantProductState.Idle)tasks.Remove(key);
            else tasks[key]=new(ev.Integration,owner,state,now,state==AssistantProductState.Done?DoneTtl:ActiveTtl,++sequence);
            if(tasks.Count>128)tasks.Remove(tasks.MinBy(x=>x.Value.LastEventAt).Key);
            return true;
        }
    }
    public AssistantAggregate Aggregate(Func<AssistantId,bool>? eligible=null)
    {
        lock(sync)
        {
            Expire();var selected=tasks.Values.Where(t=>eligible?.Invoke(t.Integration)??true).OrderByDescending(t=>t.Priority).ThenByDescending(t=>t.Sequence).ToArray();
            return new(selected.FirstOrDefault()?.State??AssistantProductState.Idle,selected.FirstOrDefault(),selected.Count(t=>t.State>=AssistantProductState.Working),generation);
        }
    }
    public void Clear(){lock(sync){tasks.Clear();duplicateEvents.Clear();generation++;}}
    private void Expire()
    {
        var now=clock.GetUtcNow();foreach(var key in tasks.Where(x=>x.Value.ExpiresAt<=now).Select(x=>x.Key).ToArray())tasks.Remove(key);
        foreach(var key in duplicateEvents.Where(x=>now-x.Value>TimeSpan.FromMinutes(5)).Select(x=>x.Key).ToArray())duplicateEvents.Remove(key);
    }
}

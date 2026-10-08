namespace AhaKey.Integrations.Tests;
public sealed class AssistantRuntimeCoordinatorTests
{
    private sealed class Clock:TimeProvider {public DateTimeOffset Now=DateTimeOffset.Parse("2026-09-21T00:00:00Z");public override DateTimeOffset GetUtcNow()=>Now;}
    private static HookEvent Event(string task,IdeEvent ev,AssistantId integration=AssistantId.Codex)=>new(integration,ev,ev.ToString()){TaskId=task};
    [Fact] public void CompletingOneTaskDoesNotNeutralizeAnother()
    {
        var c=new AssistantRuntimeCoordinator();c.Accept(Event("a",IdeEvent.UserPromptSubmit));c.Accept(Event("b",IdeEvent.UserPromptSubmit));c.Accept(Event("a",IdeEvent.Stop));
        Assert.Equal(AssistantProductState.Working,c.Aggregate().State);Assert.Equal("b",c.Aggregate().Owner!.Ownership);Assert.Equal(1,c.Aggregate().ActiveTasks);
    }
    [Fact] public void PriorityDuplicatesTtlAndReconnectAreDeterministic()
    {
        var time=new Clock();var c=new AssistantRuntimeCoordinator(time);var working=Event("a",IdeEvent.PreToolUse);
        Assert.True(c.Accept(working));Assert.False(c.Accept(working));c.Accept(Event("b",IdeEvent.PermissionRequest,AssistantId.Claude));Assert.Equal(AssistantProductState.NeedsAttention,c.Aggregate().State);
        c.Accept(Event("c",IdeEvent.Notification,AssistantId.Cursor) with{Outcome="error"});Assert.Equal(AssistantProductState.Error,c.Aggregate().State);
        time.Now=time.Now.AddMinutes(6);Assert.Equal(AssistantProductState.Idle,c.Aggregate().State);Assert.Empty(c.Sessions);
        c.Accept(working);c.Clear();Assert.Equal(AssistantProductState.Idle,c.Aggregate().State);
    }
    [Fact] public void StopWithoutIdentityCannotClearIdentifiedOwners()
    {var c=new AssistantRuntimeCoordinator();c.Accept(Event("a",IdeEvent.PreToolUse));c.Accept(new(AssistantId.Codex,IdeEvent.Stop,"Stop"));Assert.Equal(AssistantProductState.Working,c.Aggregate().State);}
    [Fact] public void ParserKeepsOnlyOpaqueOwnershipAndNeverTitleOrPrompt()
    {
        var e=HookDispatchServer.Parse("{\"cmd\":\"CodexPreToolUse\",\"taskId\":\"private-session\",\"title\":\"secret title\"}");
        Assert.NotNull(e.TaskId);Assert.DoesNotContain("private-session",e.ToString());Assert.DoesNotContain("secret title",e.ToString());
        Assert.Throws<FormatException>(()=>HookDispatchServer.Parse("{\"cmd\":\"CodexStop\",\"prompt\":\"secret\"}"));
    }
}

namespace AhaKey.Core;
public static class CodexFeedbackMapping
{
    public static IReadOnlyDictionary<IdeEventState,byte> Simple {get;}=new Dictionary<IdeEventState,byte>
    {
        [IdeEventState.UserPromptSubmit]=1,[IdeEventState.PreToolUse]=1,
        [IdeEventState.Stop]=0,[IdeEventState.TaskCompleted]=0,[IdeEventState.SessionEnd]=0,
        [IdeEventState.PermissionRequest]=0
    };
}

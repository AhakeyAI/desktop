namespace AhaKey.Core;
public enum VoicePress { Short, Long }
public sealed class VoicePressTracker
{
    private long? down;private long context;
    public bool KeyDown(long milliseconds,long currentContext)
    {if(down is not null)return false;down=milliseconds;context=currentContext;return true;}
    public VoicePress? KeyUp(long milliseconds,long currentContext,int threshold)
    {var start=down;down=null;if(start is null||context!=currentContext||milliseconds<start)return null;return milliseconds-start>=threshold?VoicePress.Long:VoicePress.Short;}
    public void Cancel()=>down=null;
}

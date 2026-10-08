namespace AhaKey.Core;

public sealed record FeedbackInput(Guid Session,HardwareProfileId Profile,string Integration,IdeEventState Event,string NativeEvent);
public enum FeedbackDisposition { Selected, Disabled, Invalid, UnverifiedEffect, Duplicate, BurstSuppressed, Busy, WrongSessionOrProfile, Accepted, Failed }
public sealed record FeedbackDecision(FeedbackDisposition Disposition,byte? Effect=null);
public sealed class PhysicalFeedbackPolicy
{
    private readonly Dictionary<(Guid Session,HardwareProfileId Profile,string Integration,IdeEventState Event),DateTimeOffset> seen=new();
    private readonly object sync=new();
    public TimeSpan Window {get;}=TimeSpan.FromSeconds(30);
    private DateTimeOffset lastOutput=DateTimeOffset.MinValue;
    // HookContract's retained text payload has no event UUID. Suppress bounded duplicates only for
    // hardware feedback; never suppress approval processing or activity history.
    public byte? Select(FeedbackInput input,bool enabled,IReadOnlyDictionary<IdeEventState,byte> map,IReadOnlySet<byte> accepted,DateTimeOffset now)
        => Decide(input,enabled,map,accepted,now).Effect;
    public FeedbackDecision Decide(FeedbackInput input,bool enabled,IReadOnlyDictionary<IdeEventState,byte> map,IReadOnlySet<byte> accepted,DateTimeOffset now)
    {
        lock(sync)
        {
            if(!enabled)return new(FeedbackDisposition.Disabled);
            if(input.Session==Guid.Empty || !Enum.IsDefined(input.Profile)||!Enum.IsDefined(input.Event))return new(FeedbackDisposition.Invalid);
            if(!map.TryGetValue(input.Event,out byte effect)||effect>0x10||!accepted.Contains(effect))return new(FeedbackDisposition.UnverifiedEffect);
            foreach(var key in seen.Where(x=>now-x.Value>=Window || x.Key.Session!=input.Session).Select(x=>x.Key).ToArray())seen.Remove(key);
            // Legacy and Studio native spellings are the same semantic event. No prompt/task body is retained.
            var identity=(input.Session,input.Profile,input.Integration,input.Event);
            if(seen.ContainsKey(identity))return new(FeedbackDisposition.Duplicate);
            // No delayed/replayed queue. Coalesce bursts and drop stale work.
            // Neutral must not be lost just because completion follows a visible effect quickly.
            if(effect!=0 && now-lastOutput<TimeSpan.FromMilliseconds(250))return new(FeedbackDisposition.BurstSuppressed);
            if(seen.Count>=64)seen.Remove(seen.MinBy(x=>x.Value).Key);
            seen[identity]=now;lastOutput=now;return new(FeedbackDisposition.Selected,effect);
        }
    }
}

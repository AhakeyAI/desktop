using AhaKey.Core;
namespace AhaKey.Core.Tests;
public sealed class VoicePressTests
{
    [Fact]public void RepeatDoesNotResetDurationAndReleaseRunsOnce()
    {var p=new VoicePressTracker();Assert.True(p.KeyDown(100,1));Assert.False(p.KeyDown(500,1));Assert.Equal(VoicePress.Long,p.KeyUp(700,1,600));Assert.Null(p.KeyUp(701,1,600));}
    [Fact]public void ContextChangeDisableAndUnmatchedReleaseCancel()
    {var p=new VoicePressTracker();Assert.Null(p.KeyUp(100,1,600));p.KeyDown(100,1);Assert.Null(p.KeyUp(200,2,600));p.KeyDown(100,1);p.Cancel();Assert.Null(p.KeyUp(800,1,600));p.KeyDown(100,1);Assert.Equal(VoicePress.Short,p.KeyUp(699,1,600));}
}

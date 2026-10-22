using AhaKey.Core;
using AhaKey.Protocol;
namespace AhaKey.Protocol.Tests;
public class ShortcutDiagnosticsTests
{
    [Fact] public void SourceDerivedNormalWindowsSaveGoldenSequence()
    {Assert.Equal(new byte[]{0xAA,0xBB,0x73,0x73,0,1,0xE0,0xE1,7,0xCC,0xDD},ShortcutDiagnostics.Preview(HardwareProfileId.Claude,PhysicalKey.K2,new("Ctrl+Shift+D")));}
    [Fact] public void BothSidesKeepEncoderSpecificInterleavedOrder()
    {Assert.True(ShortcutGesture.TryParse("Ctrl+RightCtrl+Shift+RightShift+Alt+RightAlt+Win+RightWin+A",out var g));Assert.Equal(new byte[]{0xE0,0xE4,0xE1,0xE5,0xE2,0xE6,0xE3,0xE7,4},g!.HidSequence);}
    [Fact] public void K1HasNoGenericWirePreview() => Assert.Throws<ArgumentException>(()=>ShortcutDiagnostics.Preview(HardwareProfileId.Codex,PhysicalKey.K1,new("Ctrl+A")));
}

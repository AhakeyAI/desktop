using System.Text.Json;
using AhaKey.Core;
using AhaKey.Services;
namespace AhaKey.Core.Tests;
public class KeymapCoreTests
{
    [Theory]
    [InlineData("Ctrl+Shift+P",0x0313)] [InlineData("RightCtrl+RightShift+Enter",0x3028)]
    [InlineData("Alt+RightAlt+F18",0x446D)] [InlineData("Win+RightWin+A",0x8804)]
    public void ShortcutPreservesHostModifierBits(string text,int expected)
    { Assert.True(ShortcutGesture.TryParse(text,out var g)); Assert.Equal(expected,g!.HostValue); Assert.True(ShortcutGesture.TryParse(g.Canonical,out var roundtrip)); Assert.Equal(g,roundtrip); }
    [Theory] [InlineData("Ctrl")] [InlineData("Ctrl+Ctrl+A")] [InlineData("Foo+A")] [InlineData("Ctrl+")] [InlineData("A+B")] [InlineData("")]
    public void InvalidOrModifierOnlyShortcutsAreRejected(string text) => Assert.False(ShortcutGesture.TryParse(text,out _));
    [Fact] public void CaptureRequiresExplicitStartAndConsumesOneNormalKey()
    { var c=new ShortcutCapture(); Assert.Null(c.Press("A",ShortcutModifiers.LeftCtrl)); c.Start(); Assert.Null(c.Press(null,ShortcutModifiers.RightCtrl)); Assert.True(c.IsRecording); Assert.Equal(ShortcutModifiers.RightCtrl,c.Modifiers); var g=c.Press("Enter",ShortcutModifiers.RightCtrl); Assert.Equal("RightCtrl+Enter",g!.Canonical); Assert.False(c.IsRecording); Assert.Null(c.Press("B",ShortcutModifiers.None)); }
    [Fact] public void CancelReleasesCaptureWithoutProducingAnAction()
    { var c=new ShortcutCapture();c.Start();c.UpdateModifiers(ShortcutModifiers.LeftShift);c.Cancel();Assert.False(c.IsRecording);Assert.Equal(ShortcutModifiers.None,c.Modifiers);Assert.Null(c.Press("A",ShortcutModifiers.None)); }
    [Theory] [InlineData("",true)] [InlineData("12345678901234567890",true)] [InlineData("123456789012345678901",false)] [InlineData("Принять",false)] [InlineData("接受",false)] [InlineData("a\nb",false)] [InlineData("~ !",true)]
    public void HardwareLabelBoundaryIsPrintableAscii(string value,bool valid) => Assert.Equal(valid,DeviceLabelRules.IsValid(value));
    [Fact] public void UnicodeLocalNamePersistsOutsideDeviceConfiguration()
    {
        var root=Path.Combine(Path.GetTempPath(),Guid.NewGuid().ToString());
        try {var store=new SettingsStore(root);var prefs=new ProfileSelectionService(store);prefs.Update(s=>s with{KeyLocalNames=s.KeyLocalNames.SetItem("2:1","Принять ответ 接受")});Assert.Equal("Принять ответ 接受",store.Load().KeyLocalNames["2:1"]);Assert.DoesNotContain("Принять",JsonSerializer.Serialize(DeviceConfiguration.Default));}
        finally {Directory.Delete(root,true);}
    }
    [Fact] public void DeviceLabelParticipatesInStructuralSyncEquality()
    {var a=DeviceConfiguration.Default;var p=a.Profiles[HardwareProfileId.Codex];var b=a with{Profiles=a.Profiles.SetItem(HardwareProfileId.Codex,p with{DeviceLabels=p.DeviceLabels.SetItem(PhysicalKey.K2,"Accept")})};Assert.False(a.EquivalentTo(b));}
}

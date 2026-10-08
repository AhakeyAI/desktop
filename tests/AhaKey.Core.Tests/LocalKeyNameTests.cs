using AhaKey.Core;
using AhaKey.Services;
namespace AhaKey.Core.Tests;
public sealed class LocalKeyNameTests
{
    [Fact] public void EmptyNamesReceiveDefaultsAndCustomizedNamesSurviveReload()
    {
        var root=Path.Combine(Path.GetTempPath(),"ahakey-names-"+Guid.NewGuid().ToString("N"));
        try
        {
            var store=new SettingsStore(root);var preferences=new ProfileSelectionService(store);
            foreach(var profile in Enum.GetValues<HardwareProfileId>())
                Assert.Equal(new[]{"Record","Accept","Reject","Backspace"},Enum.GetValues<PhysicalKey>().Select(key=>preferences.LocalKeyName(profile,key)));
            preferences.Update(s=>s with{KeyLocalNames=s.KeyLocalNames.SetItem("2:1","Моя команда").SetItem("2:2","")});
            var loaded=new ProfileSelectionService(new(root));
            Assert.Equal("Моя команда",loaded.LocalKeyName(HardwareProfileId.Codex,PhysicalKey.K2));
            Assert.Equal("Reject",loaded.LocalKeyName(HardwareProfileId.Codex,PhysicalKey.K3));
            Assert.Equal(2,loaded.Settings.KeyLocalNames.Count); // Defaults never rewrite user storage or device labels.
        }
        finally{if(Directory.Exists(root))Directory.Delete(root,true);}
    }
}

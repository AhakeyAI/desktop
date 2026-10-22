using AhaKey.Core;
using AhaKey.Services;
namespace AhaKey.Core.Tests;
public sealed class Phase7ProductTests:IDisposable
{
    private readonly string root=Path.Combine(Path.GetTempPath(),"ahakey-phase7",Guid.NewGuid().ToString("N"));
    private static FirmwareIdentity Legacy=>new(1,0,null,null,null,null,"observed",null,IdentitySource.PhysicalTelemetry,FirmwareDialect.LegacyWindows);
    [Fact] public void LegacyWorksWithoutFullCapabilityContract()
    {
        var catalog=new DeviceFeatureCatalog(Legacy,FeatureTransport.Usb,new(true,true,true,true));
        Assert.True(catalog.CanWriteShortcut(HardwareProfileId.Codex,PhysicalKey.K2).Available);
        Assert.False(catalog.CanWriteShortcut(HardwareProfileId.Codex,PhysicalKey.K1).Available);
        Assert.True(catalog.CanUploadDisplay(HardwareProfileId.Codex,DisplayState.Default,1).Available);
        Assert.False(catalog.CanUploadDisplay(HardwareProfileId.Cursor,DisplayState.Default,1).Available);
        Assert.False(catalog.CanUploadDisplay(HardwareProfileId.Codex,DisplayState.Default,2).Available);
        Assert.True(catalog.CanUseRuntimeLighting(1).Available);Assert.True(catalog.CanUseRuntimeLighting(0).Available);Assert.False(catalog.CanUseRuntimeLighting(2).Available);
        Assert.True(catalog.CanSetBrightness().SourceKnown);Assert.False(catalog.CanSetBrightness().Available);Assert.False(catalog.FullReadback.Available);
    }
    [Fact] public void EvidenceIsTransportAndDialectScoped()
    {
        var ble=new DeviceFeatureCatalog(Legacy,FeatureTransport.Bluetooth,new(true,true,true,true));Assert.False(ble.CanWriteShortcut(HardwareProfileId.Codex,PhysicalKey.K2).Available);Assert.True(ble.CanUseRuntimeLighting(1).Available);
        var unknown=new DeviceFeatureCatalog(FirmwareIdentity.Unknown,FeatureTransport.Usb,new(true,true,true,true));Assert.False(unknown.CanWriteShortcut(HardwareProfileId.Codex,PhysicalKey.K2).Available);
        Assert.NotNull(unknown.CanWriteShortcut(HardwareProfileId.Codex,PhysicalKey.K2).UnavailableReason);
    }
    [Fact] public void ProjectRoundTripPreservesIntentButExportStripsPhysicalClaimsAndIdentities()
    {
        var settings=new SettingsStore(root);var store=new LocalDeviceProjectStore(settings);
        var p=store.LoadOrMigrate(DeviceConfiguration.Default,new(){BleDeviceId="PRIVATE-ID",PhysicalFeedback=["2:Codex"],IntegrationAutoStart=true});
        store.Update(x=>x with{LastSuccessfullySent=x.LastSuccessfullySent.Add("Key:2:1",new("Key:2:1","hash",DateTimeOffset.UtcNow,KeyWriteProvenance.SentToDevice)),Voice=new(true,VoiceHostAction.ActivateApplication,"C:\\private.exe")});
        var path=Path.Combine(root,"export.json");store.Export(path);var text=File.ReadAllText(path);
        Assert.DoesNotContain("PRIVATE-ID",text);Assert.DoesNotContain("private.exe",text);
        var imported=store.PreviewImport(path);Assert.Empty(imported.LastSuccessfullySent);Assert.False(imported.Voice.Enabled);Assert.False(imported.IsDeviceBackup);
        Assert.True(imported.IntegrationPreferences.ServiceAutoStart);Assert.Contains("2:Codex",imported.IntegrationPreferences.PhysicalFeedback);
        var restarted=new LocalDeviceProjectStore(settings).LoadOrMigrate(DeviceConfiguration.Default,new());Assert.Single(restarted.LastSuccessfullySent);Assert.Equal(p.Id,restarted.Id);
    }
    [Fact] public void CorruptProjectIsPreservedAndNeverReplacedByDefaults()
    {
        Directory.CreateDirectory(root);var path=Path.Combine(root,"project.v1.json");File.WriteAllText(path,"{broken");var store=new LocalDeviceProjectStore(new(root));store.LoadOrMigrate(DeviceConfiguration.Default,new());
        Assert.True(store.ReadOnly);Assert.Equal("{broken",File.ReadAllText(path));Assert.Throws<IOException>(()=>store.Update(p=>p));
    }
    [Fact] public void UnknownFlashOwnershipDoesNotBecomeFree()
    {Assert.Equal("Unknown ownership",DisplayAllocationManifest.UnmanagedOwnership);}
    [Fact] public void CrashDuringKeySendRecoversUncertainWithoutInventingSuccess()
    {
        var settings=new SettingsStore(root);var store=new LocalDeviceProjectStore(settings);store.LoadOrMigrate(DeviceConfiguration.Default,new());
        store.Update(p=>p with{KeyWriteAttempts=p.KeyWriteAttempts.Add("Key:2:1",new("Key:2:1","value",DateTimeOffset.UtcNow,KeyWriteProvenance.Sending))});
        var restored=new LocalDeviceProjectStore(settings).LoadOrMigrate(DeviceConfiguration.Default,new());
        Assert.Equal(KeyWriteProvenance.OutcomeUncertain,restored.KeyWriteAttempts["Key:2:1"].State);Assert.Empty(restored.LastSuccessfullySent);
    }
    [Fact] public void MalformedOperationRecordIsPreservedWhileValidRecordsLoad()
    {
        var store=new OperationJournalStore(new(root));store.Persist(Guid.NewGuid(),new {Operation="Display upload",Outcome="OutcomeUncertain",LastConfirmedStep="81 sector 63 / 0x03F000"});
        var corrupt=Path.Combine(store.DirectoryPath,"corrupt.json");File.WriteAllText(corrupt,"{bad");
        Assert.Single(store.Read<System.Text.Json.JsonElement>());Assert.Equal("OperationJournalUnreadable",store.ErrorKey);Assert.Equal("{bad",File.ReadAllText(corrupt));
    }
    [Fact] public void StaticLegacyReceiptCannotEnableContract32DisplayGeometry()
    {
        var catalog=new DeviceFeatureCatalog(Legacy with{Dialect=FirmwareDialect.WindowsContract32},FeatureTransport.Usb,new(true,true,true,true));
        var support=catalog.CanUploadDisplay(HardwareProfileId.Codex,DisplayState.Default,1);
        Assert.False(support.Available);Assert.False(support.PhysicallyValidated);
    }
    [Fact] public void VoiceHostShortcutEncodingKeepsExtendedKeysAndRejectsRecursion()
    {
        Assert.Equal(new HostKey[]{new(0xA3,true),new(0x0D,true)},HostShortcutPlan.Create("RightCtrl+NumEnter"));
        Assert.Equal(new HostKey(0xBD),HostShortcutPlan.Create("Minus").Single());
        Assert.Equal(new HostKey(0x30),HostShortcutPlan.Create("0").Single());
        Assert.Throws<ArgumentException>(()=>HostShortcutPlan.Create("F18"));
        Assert.Throws<ArgumentException>(()=>HostShortcutPlan.Create("Ctrl+F18"));
        foreach(var key in ShortcutGesture.Keys.Keys.Where(x=>x is not ("F18" or "NonUsHash")))Assert.NotEmpty(HostShortcutPlan.Create(key));
    }
    [Fact] public void MissingCapabilityIsNotADeclaration()
    {
        var catalog=new DeviceFeatureCatalog(Legacy with{Dialect=FirmwareDialect.WindowsContract32,ReportedCapabilities=null},FeatureTransport.Usb,new());
        Assert.True(catalog.CanReadConfigResource(0).SourceKnown);Assert.False(catalog.CanReadConfigResource(0).DeclaredByDevice);Assert.False(catalog.CanReadConfigResource(0).Available);
    }
    public void Dispose(){if(Directory.Exists(root))Directory.Delete(root,true);}
}

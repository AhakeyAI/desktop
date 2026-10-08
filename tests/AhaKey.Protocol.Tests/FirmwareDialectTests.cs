using AhaKey.Core;
using AhaKey.Protocol;
namespace AhaKey.Protocol.Tests;
// Source-derived fixtures: firmware eternal-dev bc4f6e4 / source f190379. Not physical captures.
public sealed class FirmwareDialectTests
{
    [Fact] public void LegacyTelemetryDoesNotInventBuildPatchOrCapabilities()
    {
        var id=FirmwareProtocols.Identify(AhaKeyProtocol.DecodeStatus(Convert.FromHexString("AABB006432010002000123CCDD")),AhaKeyProtocol.DecodeCapabilities(Convert.FromHexString("AABB9F00CCDD")));
        Assert.Equal("1.0",id.ReportedVersion);Assert.Null(id.ReportedPatch);Assert.Null(id.KnownBuildHash);Assert.Null(id.ReportedModel);Assert.Equal(FirmwareDialect.LegacyWindows,id.Dialect);
    }
    [Fact] public void Complete32IdentityIsNotTheOnlyFeatureGate()
    {
        var caps=AhaKeyProtocol.DecodeCapabilities(Convert.FromHexString("AABB9F000302010401FF0700000801CCDD"));
        var id=FirmwareProtocols.Identify(new(100,50,1,4,2,0,ConfirmationSwitch.Auto,35,7),caps,IdentitySource.SourceDerivedFixture);
        Assert.Equal(FirmwareDialect.WindowsContract32,id.Dialect);Assert.Equal("1.4.8",id.ReportedVersion);Assert.Equal("3.2",id.ReportedProtocol);Assert.Null(id.KnownBuildHash);
        var partial=FirmwareProtocols.Identify(new(100,50,1,4,2,0,null,35,7),caps with{Bits=0});Assert.Equal(FirmwareDialect.WindowsContract32,partial.Dialect);
    }
    [Theory] [InlineData(FirmwareDialect.RuntimeTaskPictureV3)] [InlineData(FirmwareDialect.Unknown)]
    public void QuarantineCannotEmitConflictingCommands(FirmwareDialect dialect)
    {
        var adapter=FirmwareProtocols.For(dialect);Assert.Throws<NotSupportedException>(()=>adapter.QueryConfig(0,0,0));
        Assert.Throws<NotSupportedException>(()=>adapter.ValidateControl(LegacyControlCommand.SaveKeys()));
        Assert.Throws<NotSupportedException>(()=>adapter.Query(ReadOnlyQuery.Capabilities));
        Assert.IsNotType<WindowsContract32ProtocolAdapter>(adapter);
    }
    [Fact] public void PartialReadRequiresExactAddressAndDataAndRejectsEmptyAck()
    {
        var a=new WindowsContract32ProtocolAdapter();Assert.Equal("AABB9D020000CCDD",Convert.ToHexString(a.QueryConfig(2,0,0).AsSpan()));
        var f=Convert.FromHexString("AABB9D0002000200022300CCDD");var result=a.ParseConfig(f,2,0,0);Assert.Equal(new byte[]{35,0},result.Data);Assert.False(result.IsFullConfigurationBackup);
        Assert.Throws<FormatException>(()=>a.ParseConfig(Convert.FromHexString("AABB9D00CCDD"),2,0,0));
        Assert.Throws<FormatException>(()=>a.ParseConfig(f,2,0,1));Assert.Throws<ArgumentOutOfRangeException>(()=>a.QueryConfig(3,0,0));
        Assert.Throws<NotSupportedException>(()=>new LegacyWindowsProtocolAdapter().QueryConfig(2,0,0));
    }
    [Fact] public void SourceGeometryAndRawK1PolicyRemainSeparateFromLegacy()
    {
        Assert.Equal(88,WindowsContract32ProtocolAdapter.DisplaySlot(HardwareProfileId.Codex,DisplayState.Default));
        Assert.Equal(9,StaticDisplayPlan.ExpectedBinding.Start);
        Assert.Throws<InvalidOperationException>(()=>new WindowsContract32ProtocolAdapter().ValidateControl(LegacyControlCommand.K1Experiment(false)));
        Assert.Throws<InvalidOperationException>(()=>new LegacyWindowsProtocolAdapter().ValidateControl(LegacyControlCommand.Brightness(20)));
        Assert.Throws<ArgumentOutOfRangeException>(()=>new WindowsContract32ProtocolAdapter().TaskSlot(4,HardwareProfileId.Codex,2,0));
    }
}

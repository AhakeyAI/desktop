using AhaKey.Device.Ble;
using AhaKey.Protocol;
namespace AhaKey.Device.Tests;
public class LegacyCharacterizationTests
{
    [Fact] public void OrdinaryAllowlistStillRejectsProbe()=>Assert.False(AhaKeyProtocol.IsAllowedQuery(LegacyCharacterizationPermit.Request.AsSpan()));
    [Fact] public void DurablePermitAllowsExactlyOneFixedRequest()
    {
        var path=Path.Combine(Path.GetTempPath(),Guid.NewGuid()+".attempt");
        try {
            var permit=new LegacyCharacterizationPermit(path);
            var altered=LegacyCharacterizationPermit.Request.ToArray();altered[4]=1;
            Assert.Throws<BleException>(()=>permit.Consume(altered,Guid.NewGuid()));Assert.False(File.Exists(path));
            permit.Consume(LegacyCharacterizationPermit.Request.AsSpan(),Guid.NewGuid());Assert.True(File.Exists(path));
            Assert.Throws<BleException>(()=>permit.Consume(LegacyCharacterizationPermit.Request.AsSpan(),Guid.NewGuid()));
            Assert.Throws<IOException>(()=>new LegacyCharacterizationPermit(path).Consume(LegacyCharacterizationPermit.Request.AsSpan(),Guid.NewGuid()));
        } finally {if(File.Exists(path))File.Delete(path);}
    }
    [Theory]
    [InlineData("AABB9D00CCDD",LegacyQueryResult.UNKNOWN_RESPONSE)]
    [InlineData("AABB9D03CCDD",LegacyQueryResult.UNSUPPORTED_COMMAND)]
    [InlineData("AABB9D0002000200022300CCDD",LegacyQueryResult.SUPPORTED_NEWER_FORMAT)]
    [InlineData("AABB9D000201010001FF030000CCDD",LegacyQueryResult.SUPPORTED_LEGACY_FORMAT)]
    [InlineData("AABB9D0002010200022300CCDD",LegacyQueryResult.UNKNOWN_RESPONSE)]
    [InlineData("AABB9F00CCDD",LegacyQueryResult.UNKNOWN_RESPONSE)]
    [InlineData("AABB9D01CCDD",LegacyQueryResult.UNKNOWN_RESPONSE)]
    public void ClassifiesWithoutTreatingEmptyAckAsSupport(string hex,LegacyQueryResult expected)=>Assert.Equal(expected,LegacyQueryClassifier.Classify(Convert.FromHexString(hex)));
    [Fact] public void TimeoutIsExplicit()=>Assert.Equal(LegacyQueryResult.TIMEOUT,LegacyQueryClassifier.Classify([],true));
}

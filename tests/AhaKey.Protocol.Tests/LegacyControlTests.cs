using AhaKey.Core;
namespace AhaKey.Protocol.Tests;
public sealed class LegacyControlTests
{
    private static PhysicalKeyValue Value(string shortcut="Ctrl+Enter",string label="Send") {Assert.True(ShortcutGesture.TryParse(shortcut,out var g));return new(g!,label);}
    [Theory][InlineData(PhysicalKey.K2,1)][InlineData(PhysicalKey.K3,2)][InlineData(PhysicalKey.K4,3)]
    public void MinimalKeyPlanMatchesBothWindowsWriters(PhysicalKey key,byte index)
    {
        var plan=KeyWritePlan.Create(HardwareProfileId.Codex,key,Value());
        Assert.Equal(3,plan.Commands.Length);
        Assert.Equal($"AABB737302{index:X2}E028CCDD",Convert.ToHexString(plan.Commands[0].Frame.AsSpan()));
        Assert.Equal($"AABB737502{index:X2}53656E64CCDD",Convert.ToHexString(plan.Commands[1].Frame.AsSpan()));
        Assert.Equal("AABB04CCDD",Convert.ToHexString(plan.Commands[2].Frame.AsSpan()));
        Assert.All(plan.Commands,c=>Assert.Equal(ControlCategory.KeyConfiguration,c.Category));
    }
    [Fact]public void K1AndMacrosHaveNoWriteConstructor()
    {Assert.Throws<ArgumentOutOfRangeException>(()=>KeyWritePlan.Create(0,PhysicalKey.K1,Value()));Assert.Throws<ArgumentOutOfRangeException>(()=>KeyWritePlan.Create((HardwareProfileId)4,PhysicalKey.K2,Value()));}
    [Theory][InlineData("Привет")][InlineData("a\nb")][InlineData("123456789012345678901")]
    public void DescriptionRejectsWithoutSilentTruncation(string label)=>Assert.Throws<ArgumentException>(()=>KeyWritePlan.Create(0,PhysicalKey.K2,Value(label:label)));
    [Fact]public void DiffDoesNotRewriteUnchangedFields()
    {
        var old=Value();Assert.Empty(KeyWritePlan.Create(0,PhysicalKey.K2,old,old).Commands);
        var label=KeyWritePlan.Create(0,PhysicalKey.K2,Value(label:"New"),old);
        Assert.Equal(new[]{"DeviceLabel","GlobalSave"},label.Commands.Select(c=>c.Operation));
        var key=KeyWritePlan.Create(0,PhysicalKey.K2,Value("Ctrl+P"),old);
        Assert.Equal(new[]{"Shortcut","GlobalSave"},key.Commands.Select(c=>c.Operation));
    }
    [Fact]public void BehaviorEvidenceNeverBecomesReadback()
    {
        var state=new PhysicalKeyVerification();Assert.False(state.Observe(Value().Shortcut));state.Begin();state.Accept(Value());
        Assert.False(state.Observe(Value("Enter").Shortcut));Assert.Equal(PhysicalKeyWriteState.WriteAccepted,state.State);
        Assert.True(state.Observe(Value().Shortcut));Assert.Equal(PhysicalKeyWriteState.BehaviorVerified,state.State);
        state.Fail();Assert.Null(state.Accepted);Assert.Equal(PhysicalKeyWriteState.Indeterminate,state.State);
    }
    [Fact]public void ControlAcksAreSeparateFromReadOnlyAllowlist()
    {
        var command=LegacyControlCommand.Effect(1);Assert.False(AhaKeyProtocol.IsAllowedQuery(command.Frame.AsSpan()));Assert.False(UsbReportCodec.IsAllowedReport(command.UsbReport().AsSpan()));
        Assert.True(command.AcceptsResponse(Convert.FromHexString("AABB9100CCDD")));Assert.False(command.AcceptsResponse(Convert.FromHexString("AABB9101CCDD")));
        Assert.Empty(new UsbFrameAccumulator().Feed(Convert.FromHexString("AABB9100CCDD")));
        Assert.Single(new UsbFrameAccumulator(includeControlAcks:true).Feed(Convert.FromHexString("AABB9100CCDD")));
        Assert.Throws<ArgumentOutOfRangeException>(()=>LegacyControlCommand.Effect(17));Assert.Throws<ArgumentOutOfRangeException>(()=>LegacyControlCommand.Brightness(0));
    }
}

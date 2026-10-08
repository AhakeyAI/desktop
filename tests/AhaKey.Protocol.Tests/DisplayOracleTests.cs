using System.Text.Json;
using AhaKey.Protocol;
namespace AhaKey.Protocol.Tests;
public class DisplayOracleTests
{
    private static string Root=>Path.Combine(AppContext.BaseDirectory,"Fixtures","display");
    [Fact]public void ExactNativeCanvasMatchesBothHistoricalEncoders()
    {var encoded=DisplayPixelEncoder.Rgb565(File.ReadAllBytes(Path.Combine(Root,"native-canvas.rgb")));Assert.Equal(File.ReadAllBytes(Path.Combine(Root,"java.rgb565")),encoded);Assert.Equal(File.ReadAllBytes(Path.Combine(Root,"python.rgb565")),encoded);}
    [Fact]public void TimingMatchesUnmodifiedJavaOracle()
    {
        using var document=JsonDocument.Parse(File.ReadAllText(Path.Combine(Root,"java-timing.json")));
        foreach(var c in document.RootElement.EnumerateArray())
        {var p=DisplayTiming.Create(c.GetProperty("delays").EnumerateArray().Select(v=>v.GetInt32()).ToArray(),c.GetProperty("limit").GetInt32());Assert.Equal(c.GetProperty("indices").EnumerateArray().Select(v=>v.GetInt32()),p.SourceIndices);Assert.Equal(c.GetProperty("interval").GetInt32(),p.IntervalMs);Assert.Equal(c.GetProperty("duration").GetInt64(),p.SourceDurationMs);}
    }
}

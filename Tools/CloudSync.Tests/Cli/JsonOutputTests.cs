using System.Text.Json;
using CloudSync.Cli;

namespace CloudSync.Tests.Cli;

// The session serves requests concurrently on one stdout; the app tells their
// answers apart by the id on every line.
[Collection("Console")]
public class JsonOutputTests
{
    static JsonElement EmitCaptured(Action emit)
    {
        var original = Console.Out;
        var captured = new StringWriter();
        Console.SetOut(captured);
        try { emit(); }
        finally { Console.SetOut(original); }
        return JsonDocument.Parse(captured.ToString().Trim()).RootElement;
    }

    [Fact]
    public async Task LinesFromARequestCarryItsId()
    {
        var line = await Task.Run(() =>
        {
            JsonOutput.RequestId.Value = 42;
            return EmitCaptured(() => JsonOutput.Emit(new Dictionary<string, object?> { ["ok"] = true }));
        });
        Assert.Equal(42, line.GetProperty("id").GetInt64());
    }

    [Fact]
    public void LinesOutsideARequestHaveNoId()
    {
        var line = EmitCaptured(() => JsonOutput.Emit(new Dictionary<string, object?> { ["presence_ready"] = true }));
        Assert.False(line.TryGetProperty("id", out _));
    }
}

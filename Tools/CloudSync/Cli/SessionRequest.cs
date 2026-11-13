using System.Text.Json;

namespace CloudSync.Cli;

/// One request to the `session`: `{"id": N, "cmd": "enumerate", "args": {"appid": "440"}}`.
/// `args` are the command's `--name value` options without the dashes.
sealed record SessionRequest(long Id, string Command, Dictionary<string, string> Args)
{
    public static SessionRequest Parse(string line)
    {
        using var doc = JsonDocument.Parse(line);
        var root = doc.RootElement;
        var args = new Dictionary<string, string>();
        if (root.TryGetProperty("args", out var a))
            foreach (var p in a.EnumerateObject())
                args[p.Name] = p.Value.ValueKind == JsonValueKind.String ? p.Value.GetString()! : p.Value.GetRawText();
        return new SessionRequest(
            root.GetProperty("id").GetInt64(),
            root.GetProperty("cmd").GetString() ?? throw new Exception("request has no cmd"),
            args);
    }
}

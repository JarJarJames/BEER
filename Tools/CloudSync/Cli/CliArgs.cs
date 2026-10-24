namespace CloudSync.Cli;

/// Command-line argument handling shared by every command.
static class CliArgs
{
    public static string ReadToken(Dictionary<string, string> args)
    {
        if (args.TryGetValue("token-file", out var path)) return File.ReadAllText(path).Trim();
        if (args.TryGetValue("token", out var tok)) return tok.Trim();
        throw new Exception("missing --token-file or --token");
    }

    public static string Require(Dictionary<string, string> args, string key)
        => args.TryGetValue(key, out var v) ? v : throw new Exception($"missing --{key}");

    public static Dictionary<string, string> Parse(string[] a)
    {
        var d = new Dictionary<string, string>();
        for (int i = 0; i < a.Length; i++)
        {
            if (i == 0 && !a[i].StartsWith("--")) { d["_cmd"] = a[i]; continue; }
            if (a[i].StartsWith("--"))
            {
                var key = a[i].Substring(2);
                var val = (i + 1 < a.Length && !a[i + 1].StartsWith("--")) ? a[++i] : "true";
                d[key] = val;
            }
        }
        return d;
    }
}

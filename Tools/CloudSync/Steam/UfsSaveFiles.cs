using SteamKit2;

namespace CloudSync.Steam;

// Where a game keeps its Steam Cloud saves, from the app's `ufs/savefiles`
// section. Steam's client scans these folders to find new saves to upload;
// without them, the app can only find saves in folders that already have a
// cloud copy. Rules go out raw — the app expands placeholders and matches
// patterns, where it can be tested offline.
static class UfsSaveFiles
{
    /// The rules for `appid`, or an empty list when Steam has none or the
    /// lookup fails. A failure here must not fail `enumerate`: the file list
    /// is still good, and the app falls back to learning paths from it.
    public static async Task<List<Dictionary<string, object?>>> FetchAsync(SteamSession s, uint appid)
    {
        try
        {
            var apps = s.Client.GetHandler<SteamApps>()!;
            var info = await AppInfo.RequestAsync(apps, new[] { appid });
            if (!info.TryGetValue(appid, out var app) || app is null)
            {
                Console.Error.WriteLine($"enumerate: no app info for {appid}, so no save-folder rules");
                return new();
            }
            var rules = Parse(app.KeyValues);
            Console.Error.WriteLine($"enumerate: {rules.Count} save-folder rule(s)");
            return rules;
        }
        catch (Exception e)
        {
            Console.Error.WriteLine($"enumerate: couldn't read save-folder rules: {e.Message}");
            return new();
        }
    }

    /// `appInfo` is the app's root KeyValue (the one holding `ufs`).
    public static List<Dictionary<string, object?>> Parse(KeyValue appInfo)
    {
        var rules = new List<Dictionary<string, object?>>();
        foreach (var rule in appInfo["ufs"]["savefiles"].Children)
        {
            var root = rule["root"].AsString()?.Trim();
            if (string.IsNullOrEmpty(root)) continue;
            rules.Add(new Dictionary<string, object?>
            {
                ["root"] = root,
                ["path"] = rule["path"].AsString() ?? "",
                ["pattern"] = rule["pattern"].AsString() ?? "*",
                ["recursive"] = rule["recursive"].AsString() == "1",
                ["platforms"] = rule["platforms"].Children
                    .Select(p => p.AsString())
                    .Where(p => !string.IsNullOrWhiteSpace(p))
                    .ToList(),
            });
        }
        return rules;
    }
}

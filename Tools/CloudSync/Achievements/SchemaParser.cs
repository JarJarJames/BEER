using SteamKit2;

namespace CloudSync.Achievements;

/// Parses the binary VDF "schema" blob `CMsgClientGetUserStatsResponse` returns.
/// This is Valve's live UserGameStatsSchema layout (confirmed against a real
/// response for Spacewar/480, not just the older Steamworks docs):
///
///   "480"
///   {
///     "stats"
///     {
///       "0" { "type" "ACHIEVEMENTS" "bits" { "0" { "name" "ACH_X" "display" { "name" "..." "desc" "..." "icon" "..." "icon_gray" "..." } } ... } }
///       "1" { "type" "INT" "name" "some_stat" }
///     }
///   }
///
/// Two things the numeric-type/nested-icon assumption in the Steamworks docs
/// got wrong for a live response: `type` is a name ("ACHIEVEMENTS", "INT",
/// "FLOAT", "AVGRATE"), and `icon`/`icon_gray` live under `display`, not
/// directly on the bit. The stats dictionary's own numeric key (here "0")
/// for an ACHIEVEMENTS entry IS that block's stat_id.
public static class SchemaParser
{
    public static (List<AchievementDef> Achievements, List<StatDef> Stats) Parse(byte[] schema)
    {
        var kv = new KeyValue();
        using var stream = new MemoryStream(schema);
        if (!kv.TryReadAsBinary(stream))
            throw new Exception("Could not parse the game's stats schema (not valid binary VDF).");

        var achievements = new List<AchievementDef>();
        var stats = new List<StatDef>();

        // The root's one child is keyed by the appid itself; step into it if
        // present, otherwise assume `stats` sits directly under the root.
        var appRoot = kv.Children.Count == 1 && kv["stats"] == KeyValue.Invalid ? kv.Children[0] : kv;
        var statsRoot = appRoot["stats"];
        if (statsRoot == KeyValue.Invalid) return (achievements, stats);

        foreach (var stat in statsRoot.Children)
        {
            var type = stat["type"].AsString() ?? "";
            if (string.Equals(type, "ACHIEVEMENTS", StringComparison.OrdinalIgnoreCase))
            {
                if (!uint.TryParse(stat.Name, out var blockStatId)) continue;
                var bits = stat["bits"];
                if (bits == KeyValue.Invalid) continue;

                var bitIndex = 0;
                foreach (var bit in bits.Children)
                {
                    var name = bit["name"].AsString();
                    if (string.IsNullOrWhiteSpace(name)) { bitIndex++; continue; }

                    var display = bit["display"];
                    var englishName = FirstNonEmpty(display["name"]["english"].AsString(), display["name"].AsString());
                    var englishDesc = FirstNonEmpty(display["desc"]["english"].AsString(), display["desc"].AsString());
                    var hidden = display["hidden"].AsInteger(0) != 0;

                    achievements.Add(new AchievementDef(
                        Name: name!,
                        DisplayName: englishName ?? name!,
                        Description: englishDesc ?? "",
                        Hidden: hidden,
                        Icon: NullIfEmpty(display["icon"].AsString()),
                        IconGray: NullIfEmpty(display["icon_gray"].AsString()),
                        BlockStatId: blockStatId,
                        BitIndex: bitIndex));
                    bitIndex++;
                }
            }
            else
            {
                var name = stat["name"].AsString();
                if (string.IsNullOrWhiteSpace(name)) continue;
                stats.Add(new StatDef(
                    Name: name!,
                    Type: string.Equals(type, "FLOAT", StringComparison.OrdinalIgnoreCase) ? "float"
                        : string.Equals(type, "AVGRATE", StringComparison.OrdinalIgnoreCase) ? "avgrate"
                        : "int",
                    Default: stat["default"].AsFloat(0)));
            }
        }
        return (achievements, stats);
    }

    static string? NullIfEmpty(string? s) => string.IsNullOrWhiteSpace(s) ? null : s;
    static string? FirstNonEmpty(params string?[] values) => values.FirstOrDefault(v => !string.IsNullOrWhiteSpace(v));
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using SteamKit2;

/// One achievement definition from a game's Steam stats schema.
///
/// `BlockStatId` is the stat_id to use when reading/writing this
/// achievement's unlock bit — it comes from the schema's OWN numeric key for
/// its containing "ACHIEVEMENTS"-type stat entry (see `SchemaParser` below),
/// not from `ClientGetUserStatsResponse.achievement_blocks`. That response
/// only lists blocks Steam already has server-side state for, which is
/// EMPTY for an account/game that has never had a stat recorded — exactly
/// the case for a fresh test account, and the bug that made the first
/// version of this silently write nothing.
public sealed record AchievementDef(
    string Name,
    string DisplayName,
    string Description,
    bool Hidden,
    string? Icon,
    string? IconGray,
    uint BlockStatId,
    int BitIndex);

public sealed record StatDef(string Name, string Type, double Default);

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

/// Turns the raw block/bit unlock state Steam reports (and the state we send
/// back) into something the rest of the app can reason about by achievement
/// name instead of by block/bit position.
public static class AchievementState
{
    /// (stat_id, bit) -> unlock time, for every currently-unlocked
    /// achievement Steam already has server-side state for. Keyed by the
    /// block's real stat_id (not a positional index) since
    /// `achievement_blocks` isn't guaranteed to list blocks in schema order,
    /// and — the case that actually mattered here — it can be empty entirely
    /// for an account/game with no stats ever recorded.
    public static Dictionary<(uint StatId, int Bit), uint> UnlockTimes(
        IReadOnlyList<(uint StatId, IReadOnlyList<uint> UnlockTime)> blocks)
    {
        var result = new Dictionary<(uint, int), uint>();
        foreach (var block in blocks)
            for (var bit = 0; bit < block.UnlockTime.Count; bit++)
                if (block.UnlockTime[bit] != 0) result[(block.StatId, bit)] = block.UnlockTime[bit];
        return result;
    }

    /// Builds the (stat_id, 32-bit mask) pairs to send back in
    /// `CMsgClientStoreUserStats2.stats`: start from whatever Steam already
    /// has recorded for each block (so nothing already unlocked, including
    /// by the real Steam client, ever gets cleared), make sure every block
    /// the SCHEMA defines has an entry to write into — even one Steam has
    /// never recorded anything for, which is the normal state for a
    /// brand-new account/game and must not be silently skipped — then set
    /// the bits for `namesToUnlock`.
    public static List<(uint StatId, uint Mask)> BuildBlockMasks(
        IReadOnlyList<AchievementDef> achievements,
        IReadOnlyList<(uint StatId, IReadOnlyList<uint> UnlockTime)> currentBlocks,
        ISet<string> namesToUnlock)
    {
        var masks = new Dictionary<uint, uint>();
        foreach (var block in currentBlocks)
        {
            uint mask = 0;
            for (var bit = 0; bit < block.UnlockTime.Count; bit++)
                if (block.UnlockTime[bit] != 0) mask |= 1u << bit;
            masks[block.StatId] = mask;
        }

        foreach (var ach in achievements)
            if (!masks.ContainsKey(ach.BlockStatId))
                masks[ach.BlockStatId] = 0;

        foreach (var ach in achievements)
        {
            if (!namesToUnlock.Contains(ach.Name)) continue;
            masks[ach.BlockStatId] |= 1u << ach.BitIndex;
        }

        return masks.Select(kv => (kv.Key, kv.Value)).ToList();
    }
}

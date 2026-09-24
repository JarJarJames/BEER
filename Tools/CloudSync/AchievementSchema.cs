using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using SteamKit2;

/// One achievement definition from a game's Steam stats schema, plus its
/// position in the block/bit layout `ClientGetUserStats`/`ClientStoreUserStats2`
/// use to report and set unlock state: block = flat bit index / 32, bit = flat
/// bit index % 32 (Steam packs 32 achievements per block).
public sealed record AchievementDef(
    string Name,
    string DisplayName,
    string Description,
    bool Hidden,
    string? Icon,
    string? IconGray,
    int BlockIndex,
    int BitIndex);

public sealed record StatDef(string Name, string Type, double Default);

/// Parses the binary VDF "schema" blob `CMsgClientGetUserStatsResponse` returns.
/// This is Valve's well-documented UserGameStatsSchema layout:
///
///   "&lt;appid&gt;"
///   {
///     "stats"
///     {
///       "0" { "type" "4" "bits" { "0" { "name" "ACH_X" "display" { "name" {...} "desc" {...} "hidden" "0" } "icon" "..." "icon_gray" "..." } ... } }
///       "1" { "type" "1" "name" "some_stat" "default" "0" }
///     }
///   }
///
/// Type 4 is the achievement bit-field; every other type is an ordinary
/// numeric/float/avgrate stat. Achievements across every type-4 stat are
/// flattened into one continuous 0-based bit index in schema order, which is
/// how `achievement_blocks` in the get/store messages line up with them.
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

        var flatBit = 0;
        foreach (var stat in statsRoot.Children)
        {
            var type = stat["type"].AsInteger(0);
            if (type == 4)
            {
                var bits = stat["bits"];
                if (bits == KeyValue.Invalid) continue;
                foreach (var bit in bits.Children)
                {
                    var name = bit["name"].AsString();
                    if (string.IsNullOrWhiteSpace(name)) { flatBit++; continue; }

                    var display = bit["display"];
                    var englishName = FirstNonEmpty(display["name"]["english"].AsString(), display["name"].AsString());
                    var englishDesc = FirstNonEmpty(display["desc"]["english"].AsString(), display["desc"].AsString());
                    var hidden = display["hidden"].AsInteger(0) != 0;

                    achievements.Add(new AchievementDef(
                        Name: name!,
                        DisplayName: englishName ?? name!,
                        Description: englishDesc ?? "",
                        Hidden: hidden,
                        Icon: NullIfEmpty(bit["icon"].AsString()),
                        IconGray: NullIfEmpty(bit["icon_gray"].AsString()),
                        BlockIndex: flatBit / 32,
                        BitIndex: flatBit % 32));
                    flatBit++;
                }
            }
            else
            {
                var name = stat["name"].AsString();
                if (string.IsNullOrWhiteSpace(name)) continue;
                stats.Add(new StatDef(
                    Name: name!,
                    Type: type == 2 ? "float" : type == 3 ? "avgrate" : "int",
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
    /// (block, bit) -> unlock time, for every currently-unlocked achievement.
    /// `blocksInOrder` must be in the same order `ClientGetUserStatsResponse`
    /// returned them — that order IS the block index (0, 1, 2, ...).
    public static Dictionary<(int Block, int Bit), uint> UnlockTimes(
        IReadOnlyList<IReadOnlyList<uint>> blocksInOrder)
    {
        var result = new Dictionary<(int, int), uint>();
        for (var block = 0; block < blocksInOrder.Count; block++)
        {
            var times = blocksInOrder[block];
            for (var bit = 0; bit < times.Count; bit++)
                if (times[bit] != 0) result[(block, bit)] = times[bit];
        }
        return result;
    }

    /// Builds the (stat_id, 32-bit mask) pairs to send back in
    /// `CMsgClientStoreUserStats2.stats` for every achievement block: start
    /// from Steam's own current state (so nothing already unlocked, including
    /// by the real Steam client, ever gets cleared), then additionally set the
    /// bits for `namesToUnlock`.
    ///
    /// `currentBlocks` must be in the same order the schema's flattened bit
    /// index assumes (block 0, 1, 2, ...) — i.e. straight from a fresh
    /// `GetUserStats` call, not cached from an earlier one.
    public static List<(uint StatId, uint Mask)> BuildBlockMasks(
        IReadOnlyList<AchievementDef> achievements,
        IReadOnlyList<(uint StatId, IReadOnlyList<uint> UnlockTime)> currentBlocks,
        ISet<string> namesToUnlock)
    {
        var masks = new uint[currentBlocks.Count];
        for (var b = 0; b < currentBlocks.Count; b++)
        {
            uint mask = 0;
            var times = currentBlocks[b].UnlockTime;
            for (var bit = 0; bit < times.Count; bit++)
                if (times[bit] != 0) mask |= 1u << bit;
            masks[b] = mask;
        }

        foreach (var ach in achievements)
        {
            if (!namesToUnlock.Contains(ach.Name)) continue;
            if (ach.BlockIndex < 0 || ach.BlockIndex >= masks.Length) continue;
            masks[ach.BlockIndex] |= 1u << ach.BitIndex;
        }

        var result = new List<(uint, uint)>();
        for (var b = 0; b < currentBlocks.Count; b++)
            result.Add((currentBlocks[b].StatId, masks[b]));
        return result;
    }
}

using System.IO;
using SteamKit2;

// Pure-logic tests: schema parsing and unlock-bit math, no SteamKit2 session,
// no network, no Steam account. Fixtures are built with KeyValue's own binary
// writer, so these exercise the exact same reader `AchievementsGet`/
// `AchievementsStore` use against Valve's binary VDF schema format.

public class AchievementSchemaTests
{
    static byte[] BuildFixtureSchema()
    {
        var root = new KeyValue("480");
        var stats = new KeyValue("stats");
        root["stats"] = stats;

        // One achievement bit-field stat with two achievements.
        var achStat = new KeyValue("0");
        stats["0"] = achStat;
        achStat["type"] = new KeyValue("type", "4");
        var bits = new KeyValue("bits");
        achStat["bits"] = bits;

        var bit0 = new KeyValue("0");
        bits["0"] = bit0;
        bit0["name"] = new KeyValue("name", "ACH_WIN_GAME");
        var display0 = new KeyValue("display");
        bit0["display"] = display0;
        var name0 = new KeyValue("name");
        display0["name"] = name0;
        name0["english"] = new KeyValue("english", "Win the Game");
        var desc0 = new KeyValue("desc");
        display0["desc"] = desc0;
        desc0["english"] = new KeyValue("english", "Win a match");
        display0["hidden"] = new KeyValue("hidden", "0");
        bit0["icon"] = new KeyValue("icon", "https://example.com/icon0.jpg");
        bit0["icon_gray"] = new KeyValue("icon_gray", "https://example.com/icon0_gray.jpg");

        var bit1 = new KeyValue("1");
        bits["1"] = bit1;
        bit1["name"] = new KeyValue("name", "ACH_SECRET");
        var display1 = new KeyValue("display");
        bit1["display"] = display1;
        var name1 = new KeyValue("name");
        display1["name"] = name1;
        name1["english"] = new KeyValue("english", "???");
        display1["hidden"] = new KeyValue("hidden", "1");

        // One ordinary numeric stat.
        var numStat = new KeyValue("1");
        stats["1"] = numStat;
        numStat["type"] = new KeyValue("type", "1");
        numStat["name"] = new KeyValue("name", "num_wins");
        numStat["default"] = new KeyValue("default", "0");

        using var stream = new MemoryStream();
        root.SaveToStream(stream, asBinary: true);
        return stream.ToArray();
    }

    [Fact]
    public void Parse_extracts_achievements_in_flat_bit_order()
    {
        var (achievements, stats) = SchemaParser.Parse(BuildFixtureSchema());

        Assert.Equal(2, achievements.Count);
        Assert.Single(stats);

        var first = achievements[0];
        Assert.Equal("ACH_WIN_GAME", first.Name);
        Assert.Equal("Win the Game", first.DisplayName);
        Assert.Equal("Win a match", first.Description);
        Assert.False(first.Hidden);
        Assert.Equal(0, first.BlockIndex);
        Assert.Equal(0, first.BitIndex);
        Assert.Equal("https://example.com/icon0.jpg", first.Icon);

        var second = achievements[1];
        Assert.Equal("ACH_SECRET", second.Name);
        Assert.True(second.Hidden);
        Assert.Equal(0, second.BlockIndex);
        Assert.Equal(1, second.BitIndex);
        // No <icon> key was written for this one — must come back null, not "".
        Assert.Null(second.Icon);

        Assert.Equal("num_wins", stats[0].Name);
        Assert.Equal("int", stats[0].Type);
    }

    [Fact]
    public void Parse_wraps_bit_index_into_a_new_block_every_32_achievements()
    {
        var root = new KeyValue("480");
        var stats = new KeyValue("stats");
        root["stats"] = stats;
        var achStat = new KeyValue("0");
        stats["0"] = achStat;
        achStat["type"] = new KeyValue("type", "4");
        var bits = new KeyValue("bits");
        achStat["bits"] = bits;
        for (var i = 0; i < 33; i++)
        {
            var bit = new KeyValue(i.ToString());
            bits[i.ToString()] = bit;
            bit["name"] = new KeyValue("name", $"ACH_{i}");
        }
        using var stream = new MemoryStream();
        root.SaveToStream(stream, asBinary: true);

        var (achievements, _) = SchemaParser.Parse(stream.ToArray());

        Assert.Equal(33, achievements.Count);
        Assert.Equal((0, 31), (achievements[31].BlockIndex, achievements[31].BitIndex));
        Assert.Equal((1, 0), (achievements[32].BlockIndex, achievements[32].BitIndex));
    }

    [Fact]
    public void UnlockTimes_reads_nonzero_slots_as_unlocked()
    {
        var blocks = new System.Collections.Generic.List<System.Collections.Generic.IReadOnlyList<uint>>
        {
            new uint[] { 0, 1_700_000_000, 0 },
            new uint[] { 0, 0, 42 },
        };

        var unlocks = AchievementState.UnlockTimes(blocks);

        Assert.Equal(2, unlocks.Count);
        Assert.Equal(1_700_000_000u, unlocks[(0, 1)]);
        Assert.Equal(42u, unlocks[(1, 2)]);
        Assert.False(unlocks.ContainsKey((0, 0)));
    }

    [Fact]
    public void BuildBlockMasks_preserves_existing_unlocks_and_sets_new_ones()
    {
        var achievements = new System.Collections.Generic.List<AchievementDef>
        {
            new("ACH_A", "A", "", false, null, null, BlockIndex: 0, BitIndex: 0),
            new("ACH_B", "B", "", false, null, null, BlockIndex: 0, BitIndex: 1),
            new("ACH_C", "C", "", false, null, null, BlockIndex: 1, BitIndex: 0),
        };
        // Block 0 already has bit 0 unlocked server-side; block 1 is untouched.
        var currentBlocks = new System.Collections.Generic.List<(uint StatId, System.Collections.Generic.IReadOnlyList<uint> UnlockTime)>
        {
            (100u, new uint[] { 1_700_000_000, 0 }),
            (101u, new uint[] { 0 }),
        };

        var masks = AchievementState.BuildBlockMasks(achievements, currentBlocks, new System.Collections.Generic.HashSet<string> { "ACH_B", "ACH_C" });

        Assert.Equal(2, masks.Count);
        var block0 = masks[0];
        Assert.Equal(100u, block0.StatId);
        Assert.Equal(0b11u, block0.Mask); // bit 0 (already unlocked) + bit 1 (newly unlocked)

        var block1 = masks[1];
        Assert.Equal(101u, block1.StatId);
        Assert.Equal(0b1u, block1.Mask); // bit 0 newly unlocked

        // An achievement not in namesToUnlock and not already set must stay locked.
        var maskWithoutB = AchievementState.BuildBlockMasks(achievements, currentBlocks, new System.Collections.Generic.HashSet<string> { "ACH_C" });
        Assert.Equal(0b1u, maskWithoutB[0].Mask); // only the already-unlocked bit 0
    }
}

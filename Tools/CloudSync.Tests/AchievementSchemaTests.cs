using System.Collections.Generic;
using System.IO;
using System.Linq;
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

        // One achievement bit-field stat with two achievements. Field names/
        // nesting (type as a string, icon under display, the stat's own key
        // as its stat_id) match a real GetUserStats response (Spacewar/480),
        // not the Steamworks docs' numeric-type assumption the parser
        // originally (wrongly) used.
        var achStat = new KeyValue("0");
        stats["0"] = achStat;
        achStat["type"] = new KeyValue("type", "ACHIEVEMENTS");
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
        display0["icon"] = new KeyValue("icon", "https://example.com/icon0.jpg");
        display0["icon_gray"] = new KeyValue("icon_gray", "https://example.com/icon0_gray.jpg");

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
        numStat["type"] = new KeyValue("type", "INT");
        numStat["name"] = new KeyValue("name", "num_wins");
        numStat["default"] = new KeyValue("default", "0");

        using var stream = new MemoryStream();
        root.SaveToStream(stream, asBinary: true);
        return stream.ToArray();
    }

    [Fact]
    public void Parse_extracts_achievements_with_the_schema_key_as_stat_id()
    {
        var (achievements, stats) = SchemaParser.Parse(BuildFixtureSchema());

        Assert.Equal(2, achievements.Count);
        Assert.Single(stats);

        var first = achievements[0];
        Assert.Equal("ACH_WIN_GAME", first.Name);
        Assert.Equal("Win the Game", first.DisplayName);
        Assert.Equal("Win a match", first.Description);
        Assert.False(first.Hidden);
        Assert.Equal(0u, first.BlockStatId); // the stat's own key ("0") in the fixture
        Assert.Equal(0, first.BitIndex);
        Assert.Equal("https://example.com/icon0.jpg", first.Icon);

        var second = achievements[1];
        Assert.Equal("ACH_SECRET", second.Name);
        Assert.True(second.Hidden);
        Assert.Equal(0u, second.BlockStatId);
        Assert.Equal(1, second.BitIndex);
        // No <icon> key was written for this one — must come back null, not "".
        Assert.Null(second.Icon);

        Assert.Equal("num_wins", stats[0].Name);
        Assert.Equal("int", stats[0].Type);
    }

    [Fact]
    public void Parse_gives_each_separate_ACHIEVEMENTS_entry_its_own_block_stat_id()
    {
        // Real schemas with more than 32 achievements split across multiple
        // separate "ACHIEVEMENTS"-type stat entries (each capped at 32 bits),
        // not one entry that overflows — each entry's own key is its block's
        // stat_id, and its bit numbering restarts at 0.
        var root = new KeyValue("480");
        var stats = new KeyValue("stats");
        root["stats"] = stats;

        var block0 = new KeyValue("5");
        stats["5"] = block0;
        block0["type"] = new KeyValue("type", "ACHIEVEMENTS");
        var bits0 = new KeyValue("bits");
        block0["bits"] = bits0;
        var b0 = new KeyValue("0");
        bits0["0"] = b0;
        b0["name"] = new KeyValue("name", "ACH_FIRST_BLOCK");

        var block1 = new KeyValue("9");
        stats["9"] = block1;
        block1["type"] = new KeyValue("type", "ACHIEVEMENTS");
        var bits1 = new KeyValue("bits");
        block1["bits"] = bits1;
        var b1 = new KeyValue("0");
        bits1["0"] = b1;
        b1["name"] = new KeyValue("name", "ACH_SECOND_BLOCK");

        using var stream = new MemoryStream();
        root.SaveToStream(stream, asBinary: true);

        var (achievements, _) = SchemaParser.Parse(stream.ToArray());

        Assert.Equal(2, achievements.Count);
        var first = Assert.Single(achievements, a => a.Name == "ACH_FIRST_BLOCK");
        Assert.Equal((5u, 0), (first.BlockStatId, first.BitIndex));
        var second = Assert.Single(achievements, a => a.Name == "ACH_SECOND_BLOCK");
        Assert.Equal((9u, 0), (second.BlockStatId, second.BitIndex));
    }

    [Fact]
    public void UnlockTimes_reads_nonzero_slots_as_unlocked_keyed_by_real_stat_id()
    {
        var blocks = new List<(uint StatId, IReadOnlyList<uint> UnlockTime)>
        {
            (100u, new uint[] { 0, 1_700_000_000, 0 }),
            (101u, new uint[] { 0, 0, 42 }),
        };

        var unlocks = AchievementState.UnlockTimes(blocks);

        Assert.Equal(2, unlocks.Count);
        Assert.Equal(1_700_000_000u, unlocks[(100u, 1)]);
        Assert.Equal(42u, unlocks[(101u, 2)]);
        Assert.False(unlocks.ContainsKey((100u, 0)));
    }

    [Fact]
    public void BuildBlockMasks_preserves_existing_unlocks_and_sets_new_ones()
    {
        var achievements = new List<AchievementDef>
        {
            new("ACH_A", "A", "", false, null, null, BlockStatId: 100, BitIndex: 0),
            new("ACH_B", "B", "", false, null, null, BlockStatId: 100, BitIndex: 1),
            new("ACH_C", "C", "", false, null, null, BlockStatId: 101, BitIndex: 0),
        };
        // Block 100 already has bit 0 unlocked server-side; block 101 is untouched.
        var currentBlocks = new List<(uint StatId, IReadOnlyList<uint> UnlockTime)>
        {
            (100u, new uint[] { 1_700_000_000, 0 }),
            (101u, new uint[] { 0 }),
        };

        var masks = AchievementState.BuildBlockMasks(achievements, currentBlocks, new HashSet<string> { "ACH_B", "ACH_C" });

        Assert.Equal(2, masks.Count);
        Assert.Equal(0b11u, masks.Single(m => m.StatId == 100u).Mask); // bit 0 (already unlocked) + bit 1 (newly unlocked)
        Assert.Equal(0b1u, masks.Single(m => m.StatId == 101u).Mask); // bit 0 newly unlocked

        // An achievement not in namesToUnlock and not already set must stay locked.
        var maskWithoutB = AchievementState.BuildBlockMasks(achievements, currentBlocks, new HashSet<string> { "ACH_C" });
        Assert.Equal(0b1u, maskWithoutB.Single(m => m.StatId == 100u).Mask); // only the already-unlocked bit 0
    }

    [Fact]
    public void BuildBlockMasks_creates_a_block_for_a_schema_entry_Steam_never_reported()
    {
        // The live bug this guards against: for an account/game with no
        // stats ever recorded, GetUserStats returns ZERO achievement_blocks
        // even though the schema defines achievements — currentBlocks is
        // empty here on purpose. The write must still target the schema's
        // own stat_id (480 has exactly this shape: one ACHIEVEMENTS entry
        // keyed "0", achievement_blocks == [] on a fresh account).
        var achievements = new List<AchievementDef>
        {
            new("ACH_WIN_ONE_GAME", "Winner", "", false, null, null, BlockStatId: 0, BitIndex: 0),
        };
        var currentBlocks = new List<(uint StatId, IReadOnlyList<uint> UnlockTime)>();

        var masks = AchievementState.BuildBlockMasks(achievements, currentBlocks, new HashSet<string> { "ACH_WIN_ONE_GAME" });

        var block = Assert.Single(masks);
        Assert.Equal(0u, block.StatId);
        Assert.Equal(0b1u, block.Mask);
    }
}

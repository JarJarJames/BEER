using System.Text.Json;
using CloudSync.Achievements;
using CloudSync.Cli;
using CloudSync.Steam;
using SteamKit2;

namespace CloudSync.Commands;

/// `achievements-get` and `achievements-store`.
static class AchievementsCommand
{
    // Real achievement/stat schema + current unlock state for `appid`, read
    // straight from Steam over the client protocol — the same one cloud saves
    // already use, not the Publisher-key-gated Web API. Used to seed
    // gbe_fork's local steam_settings/achievements.json with the account's
    // REAL unlock state, so the emulator doesn't re-fire "just unlocked" for
    // achievements already earned on the real profile.
    public static async Task GetAsync(SteamSession s, uint appid, ulong steamid)
    {
        var resp = await s.UserStats.GetUserStatsAsync(appid, steamid, TimeSpan.FromSeconds(30));
        var (achievements, stats) = SchemaParser.Parse(resp.schema);
        var blocksInOrder = resp.achievement_blocks
            .Select(b => (StatId: b.achievement_id, UnlockTime: (IReadOnlyList<uint>)b.unlock_time))
            .ToList();
        var unlocks = AchievementState.UnlockTimes(blocksInOrder);

        var achievementJson = achievements.Select(a => (object)new Dictionary<string, object?>
        {
            ["name"] = a.Name,
            ["displayName"] = a.DisplayName,
            ["description"] = a.Description,
            ["hidden"] = a.Hidden,
            ["icon"] = a.Icon,
            ["icongray"] = a.IconGray,
            ["unlocked"] = unlocks.ContainsKey((a.BlockStatId, a.BitIndex)),
            ["unlockTime"] = unlocks.TryGetValue((a.BlockStatId, a.BitIndex), out var t) ? t : (object?)null,
        }).ToList();
        var statJson = stats.Select(st => (object)new Dictionary<string, object?>
        {
            ["name"] = st.Name,
            ["type"] = st.Type,
            ["default"] = st.Default,
        }).ToList();

        JsonOutput.Emit(new Dictionary<string, object?>
        {
            ["achievements"] = achievementJson,
            ["stats"] = statJson,
            ["crcStats"] = resp.crc_stats,
        });
    }

    // Push newly-unlocked achievements to the account's REAL Steam profile.
    // This is the write side of the pair above — see UserStatsHandler's doc
    // comment for why it's the one part of this feature that genuinely needs
    // the user's own live-account verification rather than just compiling.
    public static async Task StoreAsync(SteamSession s, uint appid, ulong steamid, string unlockedNamesPath)
    {
        var unlockedNames = JsonSerializer.Deserialize<List<string>>(
            await File.ReadAllTextAsync(unlockedNamesPath)) ?? new List<string>();

        // Re-fetch fresh — never trust a stale local view of block state,
        // since another session (the real Steam client, or a previous BEER
        // run) may have changed it since anything we cached.
        var resp = await s.UserStats.GetUserStatsAsync(appid, steamid, TimeSpan.FromSeconds(30));
        var (achievements, _) = SchemaParser.Parse(resp.schema);
        var currentBlocks = resp.achievement_blocks
            .Select(b => (StatId: b.achievement_id, UnlockTime: (IReadOnlyList<uint>)b.unlock_time))
            .ToList();

        var masks = AchievementState.BuildBlockMasks(achievements, currentBlocks, new HashSet<string>(unlockedNames));
        var storeResp = await s.UserStats.StoreUserStatsAsync(
            appid, steamid, resp.crc_stats,
            masks.Select(m => (m.StatId, m.Mask)).ToList(),
            TimeSpan.FromSeconds(30));

        JsonOutput.Emit(new Dictionary<string, object?>
        {
            ["ok"] = (EResult)storeResp.eresult == EResult.OK,
            ["eresult"] = ((EResult)storeResp.eresult).ToString(),
            ["statsOutOfDate"] = storeResp.stats_out_of_date,
            ["statsFailedValidation"] = storeResp.stats_failed_validation.Count > 0,
        });
    }
}

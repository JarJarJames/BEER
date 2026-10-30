namespace CloudSync.Achievements;

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

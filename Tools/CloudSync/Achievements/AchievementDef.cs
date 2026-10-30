namespace CloudSync.Achievements;

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

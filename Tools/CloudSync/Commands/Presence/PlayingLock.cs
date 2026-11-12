namespace CloudSync.Commands.Presence;

// Steam lets one session per account hold the "playing" slot. When another
// session is playing, Steam says so with ClientPlayingSessionState and ignores
// this session's games-played. The danger is the moment that other game lets
// go — a relaunch, a launcher handing off to the game, a network blip on the
// PC. A session that re-announces then takes the slot, and when the other
// device's game comes back Steam signs that device out with LoggedInElsewhere.
//
// So: never claim while blocked, and after a block clears wait out a cooldown
// before claiming, the same rule ArchiSteamFarm uses (MinFarmingDelayAfterBlock,
// 60 s) so it doesn't kick a user's own Steam client.
sealed class PlayingLock
{
    public static readonly TimeSpan Cooldown = TimeSpan.FromSeconds(60);

    bool _blocked;
    DateTime? _releasedAt;

    public bool Blocked => _blocked;

    public void Update(bool blocked, DateTime now)
    {
        if (_blocked && !blocked) _releasedAt = now;
        _blocked = blocked;
    }

    /// Whether announcing a game now is safe. Retracting one always is.
    public bool MayClaim(DateTime now) =>
        !_blocked && (_releasedAt is not { } released || now - released >= Cooldown);
}

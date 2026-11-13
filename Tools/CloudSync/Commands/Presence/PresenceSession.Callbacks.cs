using CloudSync.Cli;
using CloudSync.Steam;
using SteamKit2;

namespace CloudSync.Commands.Presence;

sealed partial class PresenceSession
{
    void SubscribeCallbacks()
    {
        _session.Subscribe<SteamUser.LoggedOffCallback>(cb =>
        {
            // Another BEER took this session's LoginID: reconnecting would
            // just take it back, and the two would trade it forever.
            if (cb.Result == EResult.LogonSessionReplaced)
                _displaced = true;
            // Another device took the playing slot from us. Reconnecting is
            // safe — the request work and status don't depend on the slot —
            // but count the slot as taken, so the reconnect can't grab it back
            // before Steam says the other game has stopped.
            if (cb.Result == EResult.LoggedInElsewhere)
                lock (_announceGate) _playingLock.Update(blocked: true, DateTime.UtcNow);
            JsonOutput.Emit(new Dictionary<string, object?>
            {
                ["logged_off"] = cb.Result.ToString(),
                ["displaced"] = _displaced,
            });
        });

        _session.Subscribe<SteamClient.DisconnectedCallback>(cb =>
        {
            Interlocked.Increment(ref SteamSession.CallbacksSeen);
            JsonOutput.Emit(new Dictionary<string, object?>
            {
                ["disconnected"] = true,
                ["user_initiated"] = cb.UserInitiated,
            });
        });

        _session.Subscribe<SteamClient.ConnectedCallback>(_ =>
        {
            Interlocked.Increment(ref SteamSession.CallbacksSeen);
            JsonOutput.Emit(new Dictionary<string, object?> { ["connected_callback"] = true });
        });

        // A reconnect is a brand-new logon that asserts nothing, so everything
        // this session owns has to be re-applied each time.
        _session.Subscribe<SteamUser.LoggedOnCallback>(cb =>
        {
            if (cb.Result != EResult.OK)
            {
                JsonOutput.Emit(new Dictionary<string, object?>
                {
                    ["error"] = $"Steam refused the reconnect: {cb.Result}",
                });
                return;
            }
            lock (_announceGate)
            {
                if (_currentState is { } state) _session.Client.Send(PersonaStatus.Message(state));
                // Steam only re-sends the playing state after logon if another
                // device is playing. A block from before the drop may have
                // cleared while we were away, so count it as clearing now: the
                // cooldown still applies, and a live block is re-reported.
                _playingLock.Update(blocked: false, DateTime.UtcNow);
                if (_currentApp != 0) Announce(_currentApp);
            }
            JsonOutput.Emit(new Dictionary<string, object?> { ["reconnected"] = true });
        });

        // Another device on the account started or stopped playing.
        _session.Subscribe<SteamUser.PlayingSessionStateCallback>(cb =>
        {
            lock (_announceGate)
            {
                _playingLock.Update(cb.PlayingBlocked, DateTime.UtcNow);
            }
            JsonOutput.Emit(new Dictionary<string, object?>
            {
                ["playing_blocked"] = cb.PlayingBlocked,
                ["playing_app"] = cb.PlayingAppID,
            });
        });

        // Steam's own view of this persona, pushed on every change. This is
        // where the app gets the nickname and avatar it displays, and it is the
        // ground truth for whether an announcement actually took.
        _session.Subscribe<SteamFriends.PersonaStateCallback>(cb =>
        {
            if (_session.Client.SteamID is not { } self || cb.FriendID != self) return;
            // Steam answers a targeted info request with only the fields it was
            // asked for; everything else arrives as a default — persona state
            // Offline, app id 0, no name. Reporting one of those as fact blanks
            // the name in the UI and claims the game stopped while it is still
            // running. A real update always carries the name.
            if (string.IsNullOrEmpty(cb.Name)) return;
            JsonOutput.Emit(new Dictionary<string, object?>
            {
                ["persona_name"] = cb.Name,
                ["persona_state"] = cb.State.ToString(),
                ["avatar_hash"] = cb.AvatarHash is null
                    ? null
                    : Convert.ToHexString(cb.AvatarHash).ToLowerInvariant(),
                ["presence_appid"] = cb.GameAppID,
                ["session_instances"] = cb.OnlineSessionInstances,
            });
        });
    }
}

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
            if (cb.Result is EResult.LoggedInElsewhere or EResult.LogonSessionReplaced)
                _displaced = true;
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
            _friends.SetPersonaState(_currentState);
            lock (_announceGate)
            {
                if (_currentApp != 0) Announce(_currentApp);
            }
            JsonOutput.Emit(new Dictionary<string, object?> { ["reconnected"] = true });
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

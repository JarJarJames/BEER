using CloudSync.Cli;
using CloudSync.Steam;
using SteamKit2;
using SteamKit2.Internal;

namespace CloudSync.Commands.Presence;

// One long-lived session for the whole time BEER is open: persona state,
// game announcements and play-time reads all share it.
//
// Sharing matters. Steam's games-played and persona state are both
// last-writer-wins across an account's sessions, so a second logon for
// gameplay would fight this one. One session, driven by commands.
//
// Commands arrive on stdin, one per line:
//   state <Online|Away|Invisible|Offline>
//   play <appid>
//   stop
//
// EOF ends the session. BEER holds the write end of that pipe, so EOF
// arrives if BEER dies by any means, including SIGKILL — macOS has no
// parent-death signal, and this is the only teardown that survives a force
// quit. Without it the account would be left looking permanently in-game.
sealed partial class PresenceSession
{
    readonly SteamSession _session;
    readonly ulong _steamId;
    readonly SteamFriends _friends;
    uint _currentApp;
    EPersonaState _currentState = EPersonaState.Online;

    // The keepalive thread re-announces while the command thread can be
    // retracting. Unsynchronised, a re-announce that read `_currentApp`
    // before the stop can land *after* the retraction — leaving Steam
    // believing the game is still running, permanently, because nothing
    // announces again afterwards.
    readonly object _announceGate = new();

    // Set when Steam ends the session because the account logged on
    // somewhere else. Reconnecting then would start a kick war with that
    // other client, so we stop and let the app tell the user instead.
    volatile bool _displaced;

    public PresenceSession(SteamSession session, ulong steamId)
    {
        _session = session;
        _steamId = steamId;
        _friends = session.Client.GetHandler<SteamFriends>()!;
    }

    public async Task RunAsync()
    {
        SubscribeCallbacks();

        // Keep the announcement alive. Any other session on the account — the
        // real Steam client above all — broadcasts its own games-played, and
        // the last writer wins; re-sending is how the real client makes its own
        // status stick. Also surfaces a dropped connection rather than letting
        // us sit on a dead socket believing we are still being counted.
        var stop = new CancellationTokenSource();
        var keepalive = Task.Run(() => KeepaliveAsync(stop.Token));

        // Declare "playing nothing" up front. Steam keeps the last games-played
        // it was told, so a previous session that died without retracting — a
        // crash, a force quit, a killed helper — leaves the account showing
        // in-game indefinitely, and no later session clears it because none of
        // them ever mention the stale game. This makes every launch self-healing.
        SetPlaying(0);

        JsonOutput.Emit(new Dictionary<string, object?> { ["presence_ready"] = true });

        // Seed the persona once so the app has a nickname and avatar to show
        // without waiting for Steam to push an unprompted change. PlayerName
        // has to be in the flags: Steam returns exactly the fields asked for,
        // and leaving it out is what produced nameless updates before.
        if (_session.Client.SteamID is { } seed)
            _friends.RequestFriendInfo(seed,
                EClientPersonaStateFlag.PlayerName
                | EClientPersonaStateFlag.Status
                | EClientPersonaStateFlag.GameExtraInfo
                | EClientPersonaStateFlag.Presence);

        // Console reads are synchronous underneath on Unix — ReadLineAsync
        // hands back an already-completed task after blocking. Push it onto a
        // pool thread so it can never occupy a thread something else needs.
        string? line;
        while ((line = await Task.Run(() => Console.In.ReadLine())) != null)
        {
            var parts = line.Trim().Split(' ', 2);
            if (parts.Length == 0 || parts[0].Length == 0) continue;
            try
            {
                switch (parts[0])
                {
                    // A fresh SteamKit logon's persona starts Offline, and Steam
                    // does not broadcast a game for an offline persona — so the
                    // app sends this before anything else, or nobody ever sees
                    // the game.
                    case "state":
                        if (Enum.TryParse<EPersonaState>(parts[1], true, out var wanted))
                        {
                            _currentState = wanted;
                            _friends.SetPersonaState(wanted);
                        }
                        break;

                    case "play":
                        SetPlaying(uint.Parse(parts[1]));
                        JsonOutput.Emit(new Dictionary<string, object?> { ["playing"] = _currentApp });
                        break;

                    case "stop":
                        var finished = _currentApp;
                        SetPlaying(0);
                        // Let the retraction land and Steam credit the session
                        // before re-reading the total.
                        await Task.Delay(TimeSpan.FromSeconds(2));
                        long? minutes = null;
                        try { minutes = await OwnedGamesCommand.PlaytimeMinutesAsync(_session, _steamId, finished); }
                        catch (Exception ex) { Console.Error.WriteLine($"play time re-read failed: {ex.Message}"); }
                        JsonOutput.Emit(new Dictionary<string, object?>
                        {
                            ["stopped"] = finished,
                            ["playtime_forever"] = minutes,
                        });
                        break;
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"command '{line}' failed: {ex.Message}");
            }
        }

        stop.Cancel();
        await keepalive;

        SetPlaying(0);
        _friends.SetPersonaState(EPersonaState.Offline);
        JsonOutput.Emit(new Dictionary<string, object?> { ["shutdown"] = "retracted and going offline" });
        // Let the retraction reach the CM before the caller disconnects the
        // socket underneath it.
        await Task.Delay(TimeSpan.FromSeconds(1));
    }

    void SetPlaying(uint appid)
    {
        lock (_announceGate)
        {
            _currentApp = appid;
            Announce(appid);
        }
    }

    // Tell Steam this session is playing `appid` — or, with 0, nothing at all.
    //
    // Steam credits play time to whichever logged-on client session claims to
    // be playing; the real Steam client has no special privilege here. That is
    // what lets BEER record hours for a game it launches through Wine, and it
    // is the same mechanism GameNative uses on Android.
    void Announce(uint appid)
    {
        var msg = new ClientMsgProtobuf<CMsgClientGamesPlayed>(EMsg.ClientGamesPlayedWithDataBlob);
        if (appid != 0)
            msg.Body.games_played.Add(new CMsgClientGamesPlayed.GamePlayed { game_id = appid });
        _session.Client.Send(msg);
    }
}

using CloudSync.Cli;
using CloudSync.Steam;
using SteamKit2;
using SteamKit2.Internal;

namespace CloudSync.Commands.Presence;

// BEER's one Steam session, logged on for the whole time BEER is open. Status,
// game announcements, play time, and every request the app makes (library,
// cloud saves, achievements, update checks…) all go through this one logon.
//
// One logon matters. Every extra session on the account is another chance to
// collide with the user's own Steam clients, and a burst of logons gets the
// account rate-limited.
//
// stdin, one per line:
//   state <Online|Away|Invisible|Offline>
//   play <appid>
//   stop
//   {"id": N, "cmd": "<command>", "args": {"<name>": "<value>", …}}
//     — any command CommandDispatch runs. Requests run concurrently; every
//       line one emits carries its id, and it ends with {"id": N, "done": true}.
//
// EOF ends the session. BEER holds the write end of that pipe, so EOF
// arrives if BEER dies by any means, including SIGKILL — macOS has no
// parent-death signal, and this is the only teardown that survives a force
// quit. Without it the account would be left looking permanently in-game.
sealed partial class PresenceSession
{
    readonly SteamSession _session;
    readonly SteamFriends _friends;
    uint _currentApp;

    // The status the user picked in BEER; null until the app sends one, and
    // until then this session sets none. Guarded by _announceGate: the
    // command thread writes it and a reconnect re-sends it.
    EPersonaState? _currentState;

    // The keepalive thread re-announces while the command thread can be
    // retracting. Unsynchronised, a re-announce that read `_currentApp`
    // before the stop can land *after* the retraction — leaving Steam
    // believing the game is still running, permanently, because nothing
    // announces again afterwards.
    readonly object _announceGate = new();

    // Guarded by _announceGate, like _currentApp.
    readonly PlayingLock _playingLock = new();

    // Set when another logon took this session's LoginID — almost always a
    // second copy of BEER. Reconnecting would start a kick war with it, so we
    // stop and let the app tell the user instead.
    volatile bool _displaced;

    public PresenceSession(SteamSession session)
    {
        _session = session;
        _friends = session.Client.GetHandler<SteamFriends>()!;
        session.Client.AddHandler(new SelfPersonaTrace());
    }

    public async Task RunAsync()
    {
        SubscribeCallbacks();

        // Keep the announcement alive. Any other session on the account — the
        // real Steam client above all — broadcasts its own games-played, and
        // the last writer wins; re-sending is how the real client makes its own
        // status stick. It never claims over another device that is playing,
        // though: see PlayingLock. Also surfaces a dropped connection rather than letting
        // us sit on a dead socket believing we are still being counted.
        var stop = new CancellationTokenSource();
        var keepalive = Task.Run(() => KeepaliveAsync(stop.Token));

        // Nothing about playing is sent until a game starts. A launch used to
        // open with an empty games-played; GameNative, which runs beside the
        // user's desktop Steam client without signing it out of Friends, never
        // sends one, and BEER did on every launch (#65). A game announced by an
        // earlier session that died goes with that session's connection.
        await DiagnoseStepAsync(1, "logged on; nothing else sent yet");

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
        await DiagnoseStepAsync(2, "asked Steam for your profile (name, avatar)");
        var statusStepDone = !Diagnosing;

        // Console reads are synchronous underneath on Unix — ReadLineAsync
        // hands back an already-completed task after blocking. Push it onto a
        // pool thread so it can never occupy a thread something else needs.
        string? line;
        while ((line = await Task.Run(() => Console.In.ReadLine())) != null)
        {
            if (line.StartsWith('{'))
            {
                Serve(line);
                continue;
            }
            var parts = line.Trim().Split(' ', 2);
            if (parts.Length == 0 || parts[0].Length == 0) continue;
            try
            {
                switch (parts[0])
                {
                    case "state":
                        if (Enum.TryParse<EPersonaState>(parts[1], true, out var wanted))
                            ApplyState(wanted);
                        if (!statusStepDone)
                        {
                            statusStepDone = true;
                            await DiagnoseStepAsync(3, $"sent your status ({parts[1]})");
                            JsonOutput.Emit(new Dictionary<string, object?> { ["diagnose"] = "done: library, cloud and the rest run now" });
                        }
                        break;

                    case "play":
                        bool blocked;
                        lock (_announceGate)
                        {
                            SetPlaying(uint.Parse(parts[1]));
                            blocked = !_playingLock.MayClaim(DateTime.UtcNow);
                        }
                        JsonOutput.Emit(new Dictionary<string, object?>
                        {
                            ["playing"] = _currentApp,
                            ["blocked_by_other_session"] = blocked,
                        });
                        break;

                    case "stop":
                        var finished = _currentApp;
                        SetPlaying(0);
                        // Let the retraction land and Steam credit the session
                        // before re-reading the total.
                        await Task.Delay(TimeSpan.FromSeconds(2));
                        long? minutes = null;
                        try { minutes = await OwnedGamesCommand.PlaytimeMinutesAsync(_session, _session.Client.SteamID!.ConvertToUInt64(), finished); }
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

        // Retract a game still announced, but never set the persona Offline
        // here. Persona state belongs to the account, not this session:
        // Offline signs every device out of Friends & Chat, so quitting BEER
        // knocked the user's Steam client and phone offline too. Logging off
        // is enough; Steam drops this session and the others keep their status.
        bool announced;
        lock (_announceGate) announced = _currentApp != 0;
        if (announced)
        {
            SetPlaying(0);
            // Let the retraction reach the CM before the caller disconnects
            // the socket underneath it.
            await Task.Delay(TimeSpan.FromSeconds(1));
        }
        JsonOutput.Emit(new Dictionary<string, object?> { ["shutdown"] = announced ? "retracted" : "nothing to retract" });
    }

    // BEER_STEAM_DIAGNOSE=1: space out everything the session sends at launch
    // so a person watching their other Steam clients can see which step, if
    // any, signs them out of Friends. Requests wait until the steps are done.
    static readonly bool Diagnosing = Environment.GetEnvironmentVariable("BEER_STEAM_DIAGNOSE") == "1";
    static readonly TimeSpan DiagnosePause = TimeSpan.FromSeconds(15);

    static async Task DiagnoseStepAsync(int step, string what)
    {
        if (!Diagnosing) return;
        JsonOutput.Emit(new Dictionary<string, object?> { ["diagnose"] = $"step {step}/3: {what}. Waiting {DiagnosePause.TotalSeconds:0} s…" });
        await Task.Delay(DiagnosePause);
    }

    void Serve(string line)
    {
        long id = 0;
        try
        {
            var request = SessionRequest.Parse(line);
            id = request.Id;
            _ = Task.Run(() => CommandDispatch.ServeAsync(_session, request.Id, request.Command, request.Args));
        }
        catch (Exception ex)
        {
            // A request that won't parse still has to end, or the app waits on it.
            JsonOutput.Emit(new Dictionary<string, object?> { ["id"] = id, ["error"] = $"bad request: {ex.Message}" });
            JsonOutput.Emit(new Dictionary<string, object?> { ["id"] = id, ["done"] = true });
        }
    }

    // Persona state belongs to the account, so this session only ever sends
    // the one the user picked in BEER, exactly as they picked it.
    void ApplyState(EPersonaState wanted)
    {
        lock (_announceGate) _currentState = wanted;
        _session.Client.Send(PersonaStatus.Message(wanted));
        JsonOutput.Emit(new Dictionary<string, object?> { ["status_sent"] = wanted.ToString() });
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
    //
    // Callers hold _announceGate. While another device is playing, or just
    // after it stopped, the announcement is held back (see PlayingLock); the
    // keepalive sends it once claiming is safe.
    void Announce(uint appid)
    {
        if (appid != 0 && !_playingLock.MayClaim(DateTime.UtcNow)) return;
        var msg = new ClientMsgProtobuf<CMsgClientGamesPlayed>(EMsg.ClientGamesPlayedWithDataBlob);
        if (appid != 0)
            msg.Body.games_played.Add(new CMsgClientGamesPlayed.GamePlayed { game_id = appid });
        _session.Client.Send(msg);
    }
}

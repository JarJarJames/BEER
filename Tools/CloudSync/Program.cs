using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.IO.IsolatedStorage;
using System.Linq;
using System.Net.Http;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using ProtoBuf;
using SteamKit2;
using SteamKit2.Authentication;
using SteamKit2.Internal;

// CloudSync — a tiny native helper that does REAL bidirectional Steam Cloud
// sync over the Steam client protocol (CM + unified messages), using the same
// SteamKit2 library DepotDownloader is built on.
//
// Why this exists: the Steam *Web* API (api.steampowered.com/ICloudService)
// gates EnumerateUserFiles/upload behind a Publisher key. The Steam *client*
// protocol does not — it authenticates with the user's own refresh token, the
// same token BEER already obtains via QR sign-in. This unlocks PUSH,
// which the web-scrape path could never do.
//
// All commands print a single JSON object to stdout. Human/log noise goes to
// stderr. Exit code 0 = ok, non-zero = failure (with {"error":...} on stdout).
//
// Commands:
//   enumerate --appid N
//   dlc       --appid N
//   presence  --steamid S   (long-lived; stdin commands, until stdin closes)
//   download  --appid N --file "<ufs filename>" --out <localPath>
//   upload    --appid N --file "<ufs filename>" --in <localPath> [--mtime <unix>]
//   prepare-depot-auth --depot-executable <path>
//
// Auth (all commands): --token <refreshToken> --account <name>
//   Prefer --token-file <path> so the token never appears in argv / ps output.

static class Program
{
    static async Task<int> Main(string[] rawArgs)
    {
        var args = ParseArgs(rawArgs);
        if (rawArgs.Length == 0 || !args.TryGetValue("_cmd", out var cmd))
        {
            Console.Error.WriteLine("usage: CloudSync <enumerate|dlc|download|upload> --token-file F --account NAME --appid N [...]");
            return 2;
        }

        try
        {
            // `auth` needs no prior token — it mints one via QR.
            if (cmd == "auth")
            {
                await Auth();
                return 0;
            }

            // DepotDownloader has no CLI flag for an existing SteamClient
            // refresh token. Bridge BEER's Keychain-owned token into its
            // account cache; Swift removes this file as soon as the process
            // exits and records its path for crash cleanup.
            if (cmd == "prepare-depot-auth")
            {
                var bridgeToken = ReadToken(args);
                var bridgeAccount = Require(args, "account");
                var config = PrepareDepotAuth(
                    Require(args, "depot-executable"), bridgeAccount, bridgeToken);
                EmitJson(new Dictionary<string, object?>
                {
                    ["prepared"] = true,
                    ["config_path"] = config,
                });
                return 0;
            }

            var token = ReadToken(args);
            var account = Require(args, "account");
            uint appid = args.TryGetValue("appid", out var aid) ? uint.Parse(aid) : 0; // not needed by ownedgames

            using var session = await SteamSession.LogOnAsync(
                account, token,
                cmd == "presence" ? SteamSession.PresenceLoginID : SteamSession.CommandLoginID);
            try
            {
                switch (cmd)
                {
                    case "ownedgames": await OwnedGames(session, ulong.Parse(Require(args, "steamid"))); break;
                    case "dlc": await Dlc(session, appid); break;
                    case "presence":
                        await Presence(session, ulong.Parse(Require(args, "steamid")));
                        break;
                    case "enumerate": await Enumerate(session, appid); break;
                    case "batch": await Batch(session, appid, Require(args, "jobs")); break;
                    case "download":
                        await DownloadCore(session, appid, Require(args, "file"), Require(args, "out"));
                        EmitJson(new Dictionary<string, object?> { ["downloaded"] = true });
                        break;
                    case "upload":
                        long mtime = args.TryGetValue("mtime", out var mt) ? long.Parse(mt) : DateTimeOffset.UtcNow.ToUnixTimeSeconds();
                        await UploadCore(session, appid, Require(args, "file"), Require(args, "in"), mtime);
                        EmitJson(new Dictionary<string, object?> { ["uploaded"] = true });
                        break;
                    default:
                        Console.Error.WriteLine($"unknown command: {cmd}");
                        return 2;
                }
            }
            finally
            {
                session.Disconnect();
            }
            return 0;
        }
        catch (Exception ex)
        {
            var payload = new Dictionary<string, object?> { ["error"] = ex.Message };
            // Classify logon failures so the app shows the right message and
            // doesn't push a needless re-sign-in for a transient throttle.
            if (ex is LogonFailedException lfe)
            {
                if (lfe.IsRateLimited) payload["rate_limited"] = true;
                else payload["auth_failed"] = true;
            }
            EmitJson(payload);
            Console.Error.WriteLine(ex);
            return 1;
        }
    }

    // MARK: - Commands

    static string PrepareDepotAuth(string depotExecutable, string account, string token)
    {
        var configPath = DepotAuthConfigPath(depotExecutable);
        Directory.CreateDirectory(Path.GetDirectoryName(configPath)!);

        var settings = new DepotAccountSettings();
        settings.LoginTokens[account] = token;

        var tempPath = $"{configPath}.{Guid.NewGuid():N}.tmp";
        try
        {
            using (var file = new FileStream(tempPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            using (var deflate = new DeflateStream(file, CompressionMode.Compress))
                Serializer.Serialize(deflate, settings);

            if (!OperatingSystem.IsWindows())
                File.SetUnixFileMode(tempPath, UnixFileMode.UserRead | UnixFileMode.UserWrite);
            File.Move(tempPath, configPath, overwrite: true);
        }
        finally
        {
            if (File.Exists(tempPath)) File.Delete(tempPath);
        }
        return configPath;
    }

    static string DepotAuthConfigPath(string depotExecutable)
    {
        var isolatedRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "IsolatedStorage");
        Directory.CreateDirectory(isolatedRoot);

        var first = Directory.GetDirectories(isolatedRoot)
            .FirstOrDefault(path => Path.GetFileName(path).Length == 12);
        if (first == null)
        {
            first = Path.Combine(isolatedRoot, Path.GetRandomFileName());
            Directory.CreateDirectory(first);
        }
        var second = Directory.GetDirectories(first)
            .FirstOrDefault(path => Path.GetFileName(path).Length == 12);
        if (second == null)
        {
            second = Path.Combine(first, Path.GetRandomFileName());
            Directory.CreateDirectory(second);
        }

        var identityHelper = typeof(IsolatedStorageFile).Assembly
            .GetType("System.Security.IdentityHelper")
            ?? throw new Exception("Could not locate .NET isolated-storage identity support.");
        var hashMethod = identityHelper.GetMethod(
            "GetNormalizedUriHash", BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new Exception("Could not calculate DepotDownloader's isolated-storage identity.");
        var executableUri = new Uri(Path.GetFullPath(depotExecutable));
        var hash = hashMethod.Invoke(null, [executableUri]) as string
            ?? throw new Exception("Could not calculate DepotDownloader's isolated-storage path.");

        return Path.Combine(second, $"Url.{hash}", "AssemFiles", "account.config");
    }

    [ProtoContract]
    sealed class DepotAccountSettings
    {
        [ProtoMember(2)]
        public ConcurrentDictionary<string, int> ContentServerPenalty { get; } = new();

        [ProtoMember(4)]
        public Dictionary<string, string> LoginTokens { get; } =
            new(StringComparer.OrdinalIgnoreCase);

        [ProtoMember(5)]
        public Dictionary<string, string> GuardData { get; } =
            new(StringComparer.OrdinalIgnoreCase);
    }

    // QR sign-in that yields a SteamClient-audience refresh token (the kind the
    // Cloud client protocol accepts). Emits the challenge URL as JSON so the
    // Swift UI can render the QR, re-emits on rotation, then emits the token.
    static async Task Auth()
    {
        using var session = await SteamSession.ConnectOnlyAsync();

        var authSession = await session.Client.Authentication.BeginAuthSessionViaQRAsync(new AuthSessionDetails
        {
            PlatformType = EAuthTokenPlatformType.k_EAuthTokenPlatformType_SteamClient,
            DeviceFriendlyName = "BEER for Mac",
            ClientOSType = EOSType.MacOS1020,
            IsPersistentSession = true,
        });

        void EmitChallenge() => EmitJson(new Dictionary<string, object?>
        {
            ["challenge_url"] = authSession.ChallengeURL,
        });

        authSession.ChallengeURLChanged = EmitChallenge;
        EmitChallenge();

        var poll = await authSession.PollingWaitForResultAsync();
        session.Disconnect();

        EmitJson(new Dictionary<string, object?>
        {
            ["authenticated"] = true,
            ["account"] = poll.AccountName,
            ["refresh_token"] = poll.RefreshToken,
        });
    }

    static async Task OwnedGames(SteamSession s, ulong steamid)
    {
        var player = s.Unified.CreateService<Player>();
        var resp = await player.GetOwnedGames(new CPlayer_GetOwnedGames_Request
        {
            steamid = steamid,
            include_appinfo = true,
            include_played_free_games = true,
            include_free_sub = false,
        });
        if (resp.Result != EResult.OK)
            throw new Exception($"GetOwnedGames failed: {resp.Result}");

        var games = resp.Body.games.Select(g => (object)new Dictionary<string, object?>
        {
            ["appid"] = g.appid,
            ["name"] = g.name,
            ["img_icon_url"] = g.img_icon_url,
            ["playtime_forever"] = g.playtime_forever,
            ["rtime_last_played"] = g.rtime_last_played,
        }).ToList();
        EmitJson(new Dictionary<string, object?> { ["games"] = games });
    }

    // Tell Steam this session is playing `appid` — or, with 0, nothing at all.
    //
    // Steam credits play time to whichever logged-on client session claims to
    // be playing; the real Steam client has no special privilege here. That is
    // what lets BEER record hours for a game it launches through Wine, and it
    // is the same mechanism GameNative uses on Android.
    static void Announce(SteamSession s, uint appid)
    {
        var msg = new ClientMsgProtobuf<CMsgClientGamesPlayed>(EMsg.ClientGamesPlayedWithDataBlob);
        if (appid != 0)
            msg.Body.games_played.Add(new CMsgClientGamesPlayed.GamePlayed { game_id = appid });
        s.Client.Send(msg);
    }

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
    static async Task Presence(SteamSession s, ulong steamid)
    {
        var friends = s.Client.GetHandler<SteamFriends>()!;
        uint currentApp = 0;
        // The keepalive thread re-announces while the command thread can be
        // retracting. Unsynchronised, a re-announce that read `currentApp`
        // before the stop can land *after* the retraction — leaving Steam
        // believing the game is still running, permanently, because nothing
        // announces again afterwards.
        var announceGate = new object();

        void SetPlaying(uint appid)
        {
            lock (announceGate)
            {
                currentApp = appid;
                Announce(s, appid);
            }
        }
        var currentState = EPersonaState.Online;
        // Set when Steam ends the session because the account logged on
        // somewhere else. Reconnecting then would start a kick war with that
        // other client, so we stop and let the app tell the user instead.
        var displaced = false;

        s.Subscribe<SteamUser.LoggedOffCallback>(cb =>
        {
            if (cb.Result is EResult.LoggedInElsewhere or EResult.LogonSessionReplaced)
                displaced = true;
            EmitJson(new Dictionary<string, object?>
            {
                ["logged_off"] = cb.Result.ToString(),
                ["displaced"] = displaced,
            });
        });

        s.Subscribe<SteamClient.DisconnectedCallback>(cb =>
        {
            Interlocked.Increment(ref SteamSession.CallbacksSeen);
            EmitJson(new Dictionary<string, object?>
            {
                ["disconnected"] = true,
                ["user_initiated"] = cb.UserInitiated,
            });
        });

        s.Subscribe<SteamClient.ConnectedCallback>(_ =>
        {
            Interlocked.Increment(ref SteamSession.CallbacksSeen);
            EmitJson(new Dictionary<string, object?> { ["connected_callback"] = true });
        });

        // A reconnect is a brand-new logon that asserts nothing, so everything
        // this session owns has to be re-applied each time.
        s.Subscribe<SteamUser.LoggedOnCallback>(cb =>
        {
            if (cb.Result != EResult.OK)
            {
                EmitJson(new Dictionary<string, object?>
                {
                    ["error"] = $"Steam refused the reconnect: {cb.Result}",
                });
                return;
            }
            friends.SetPersonaState(currentState);
            lock (announceGate)
            {
                if (currentApp != 0) Announce(s, currentApp);
            }
            EmitJson(new Dictionary<string, object?> { ["reconnected"] = true });
        });

        // Steam's own view of this persona, pushed on every change. This is
        // where the app gets the nickname and avatar it displays, and it is the
        // ground truth for whether an announcement actually took.
        s.Subscribe<SteamFriends.PersonaStateCallback>(cb =>
        {
            if (s.Client.SteamID is not { } self || cb.FriendID != self) return;
            // Steam answers a targeted info request with only the fields it was
            // asked for; everything else arrives as a default — persona state
            // Offline, app id 0, no name. Reporting one of those as fact blanks
            // the name in the UI and claims the game stopped while it is still
            // running. A real update always carries the name.
            if (string.IsNullOrEmpty(cb.Name)) return;
            EmitJson(new Dictionary<string, object?>
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

        // Keep the announcement alive. Any other session on the account — the
        // real Steam client above all — broadcasts its own games-played, and
        // the last writer wins; re-sending is how the real client makes its own
        // status stick. Also surfaces a dropped connection rather than letting
        // us sit on a dead socket believing we are still being counted.
        var stop = new CancellationTokenSource();
        var keepalive = Task.Run(async () =>
        {
            var attempts = 0;
            var ticks = 0;
            var lastPump = -1L;
            while (!stop.IsCancellationRequested)
            {
                try { await Task.Delay(TimeSpan.FromSeconds(5), stop.Token); }
                catch (OperationCanceledException) { break; }

                // A pump that stops advancing has stopped delivering callbacks,
                // and every symptom of that is silent: the socket reconnects,
                // the process stays alive, and nothing Steam sends is ever
                // acted on again. Fail loudly instead of flapping for hours.
                if (SteamSession.PumpIterations == lastPump)
                {
                    EmitJson(new Dictionary<string, object?>
                    {
                        ["error"] = "The Steam callback pump stopped responding, so status and play time can't be tracked. Restarting BEER should clear it.",
                        ["fatal"] = true,
                    });
                    Environment.Exit(1);
                }
                lastPump = SteamSession.PumpIterations;

                Console.Error.WriteLine(
                    $"tick: connected={s.Client.IsConnected} steamid={s.Client.SteamID} " +
                    $"pump={SteamSession.PumpIterations} faults={SteamSession.PumpFaults} " +
                    $"callbacks={SteamSession.CallbacksSeen}");

                if (s.Client.IsConnected)
                {
                    if (attempts > 0)
                        EmitJson(new Dictionary<string, object?> { ["connection_restored"] = true });
                    attempts = 0;
                    lock (announceGate)
                    {
                        if (currentApp != 0) Announce(s, currentApp);
                    }

                    // Persona state is last-writer-wins across an account's
                    // sessions, exactly like games-played, so it needs the same
                    // periodic defence — but far less often, since nothing else
                    // asserts it continuously and Steam pushes the real value
                    // back unprompted whenever it changes.
                    if (++ticks % 12 == 0) friends.SetPersonaState(currentState);
                    continue;
                }

                // Displaced by another logon on this account — almost always
                // the real Steam client. Reconnecting would just kick that one
                // back, and the two would trade the account indefinitely.
                if (displaced)
                {
                    EmitJson(new Dictionary<string, object?>
                    {
                        ["error"] = "Steam signed this session out because the account logged on somewhere else. Reopen BEER to restore status and play-time tracking.",
                        ["fatal"] = true,
                    });
                    // Nothing this process can still do is useful, and the app
                    // watches for it exiting to clear the status it shows.
                    Environment.Exit(1);
                    return;
                }

                // A CM dropping a long-lived client is routine, so reconnect —
                // the session's existing ConnectedCallback logs back on. Back
                // off so a persistent outage doesn't hammer Steam's rate limit.
                attempts++;
                if (attempts > 10)
                {
                    EmitJson(new Dictionary<string, object?>
                    {
                        ["error"] = "Lost the Steam connection and couldn't get it back. Status and play time aren't being recorded.",
                        ["fatal"] = true,
                    });
                    Environment.Exit(1);
                    return;
                }
                EmitJson(new Dictionary<string, object?> { ["reconnecting"] = attempts });
                try { s.Client.Connect(); } catch { /* next tick retries */ }
                try { await Task.Delay(TimeSpan.FromSeconds(Math.Min(5 * attempts, 30)), stop.Token); }
                catch (OperationCanceledException) { break; }
            }
        });

        // Declare "playing nothing" up front. Steam keeps the last games-played
        // it was told, so a previous session that died without retracting — a
        // crash, a force quit, a killed helper — leaves the account showing
        // in-game indefinitely, and no later session clears it because none of
        // them ever mention the stale game. This makes every launch self-healing.
        SetPlaying(0);

        EmitJson(new Dictionary<string, object?> { ["presence_ready"] = true });

        // Seed the persona once so the app has a nickname and avatar to show
        // without waiting for Steam to push an unprompted change. PlayerName
        // has to be in the flags: Steam returns exactly the fields asked for,
        // and leaving it out is what produced nameless updates before.
        if (s.Client.SteamID is { } seed)
            friends.RequestFriendInfo(seed,
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
                            currentState = wanted;
                            friends.SetPersonaState(wanted);
                        }
                        break;

                    case "play":
                        SetPlaying(uint.Parse(parts[1]));
                        EmitJson(new Dictionary<string, object?> { ["playing"] = currentApp });
                        break;

                    case "stop":
                        var finished = currentApp;
                        SetPlaying(0);
                        // Let the retraction land and Steam credit the session
                        // before re-reading the total.
                        await Task.Delay(TimeSpan.FromSeconds(2));
                        long? minutes = null;
                        try { minutes = await PlaytimeMinutes(s, steamid, finished); }
                        catch (Exception ex) { Console.Error.WriteLine($"play time re-read failed: {ex.Message}"); }
                        EmitJson(new Dictionary<string, object?>
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
        friends.SetPersonaState(EPersonaState.Offline);
        EmitJson(new Dictionary<string, object?> { ["shutdown"] = "retracted and going offline" });
        // Let the retraction reach the CM before the caller disconnects the
        // socket underneath it.
        await Task.Delay(TimeSpan.FromSeconds(1));
    }

    /// Total minutes Steam has recorded for one app.
    static async Task<long?> PlaytimeMinutes(SteamSession s, ulong steamid, uint appid)
    {
        var player = s.Unified.CreateService<Player>();
        var req = new CPlayer_GetOwnedGames_Request
        {
            steamid = steamid,
            include_appinfo = false,
            include_played_free_games = true,
            include_free_sub = false,
        };
        req.appids_filter.Add(appid);

        var resp = await player.GetOwnedGames(req);
        if (resp.Result != EResult.OK)
            throw new Exception($"GetOwnedGames failed: {resp.Result}");
        return resp.Body.games.FirstOrDefault(g => g.appid == appid)?.playtime_forever;
    }

    // Report every DLC Steam lists for `appid`, flagged with whether this
    // account actually owns it.
    //
    // There is no "GetOwnedDLC" API — IPlayerService.GetOwnedGames returns
    // games only, never DLC. Ownership is derived the same way the real Steam
    // client (and DepotDownloader's AccountHasAccess) derives it: take the
    // packages this account is licensed for, ask PICS which appids each package
    // grants, and intersect that set with the app's DLC list.
    static async Task Dlc(SteamSession s, uint appid)
    {
        if (appid == 0) throw new Exception("dlc requires --appid");
        var apps = s.Client.GetHandler<SteamApps>()!;

        // Independent of everything below, and gated on a push Steam sends just
        // after logon — kick it off first and collect it once the DLC ids are known.
        var ownedTask = OwnedAppIds(s, apps);

        var baseInfo = await RequestAppInfo(apps, new[] { appid });
        if (!baseInfo.TryGetValue(appid, out var baseApp) || baseApp is null)
            throw new Exception($"Steam returned no app info for {appid}");

        var dlcIds = new List<uint>();
        var seen = new HashSet<uint>();
        void AddDlc(uint id)
        {
            if (id != 0 && id != appid && seen.Add(id)) dlcIds.Add(id);
        }

        // The canonical list: appinfo → extended → listofdlc, comma separated.
        var listOfDlc = baseApp.KeyValues["extended"]["listofdlc"].AsString();
        if (!string.IsNullOrWhiteSpace(listOfDlc))
        {
            foreach (var part in listOfDlc.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                if (uint.TryParse(part, out var id)) AddDlc(id);
        }

        // Older titles omit listofdlc and instead tag the DLC's depot inside the
        // base app's depot section with a `dlcappid` key. Pick those up too.
        foreach (var depot in baseApp.KeyValues["depots"].Children)
        {
            var tag = depot["dlcappid"];
            if (tag != KeyValue.Invalid && uint.TryParse(tag.Value, out var id)) AddDlc(id);
        }

        var dlcInfo = await RequestAppInfo(apps, dlcIds);
        var owned = await ownedTask;

        var result = new List<object>();
        foreach (var id in dlcIds)
        {
            dlcInfo.TryGetValue(id, out var info);
            var common = info?.KeyValues["common"];
            var name = common?["name"].AsString();
            result.Add(new Dictionary<string, object?>
            {
                ["appid"] = id,
                ["name"] = string.IsNullOrWhiteSpace(name) ? $"DLC {id}" : name,
                ["owned"] = owned.Contains(id),
                // Whether there is anything to download. Licence-only DLC
                // (season passes, artbooks) carry no installable depot, so the
                // UI can mark them "nothing to install" instead of failing.
                ["has_depots"] = info is not null && HasInstallableDepots(info),
            });
        }
        EmitJson(new Dictionary<string, object?> { ["dlc"] = result });
    }

    /// Every appid granted by the packages this account holds a licence for.
    static async Task<HashSet<uint>> OwnedAppIds(SteamSession s, SteamApps apps)
    {
        var licenses = await s.LicensesAsync();
        var requests = licenses
            .GroupBy(l => l.PackageID)
            .Select(g =>
            {
                var req = new SteamKit2.SteamApps.PICSRequest(g.Key);
                var token = g.Select(l => l.AccessToken).FirstOrDefault(t => t != 0);
                if (token != 0) req.AccessToken = token;
                return req;
            })
            .ToList();

        var owned = new HashSet<uint>();
        if (requests.Count == 0) return owned;

        // PICS rejects very large batches; chunk to stay well inside its limit.
        foreach (var chunk in requests.Chunk(500))
        {
            var info = await apps.PICSGetProductInfo(new List<SteamKit2.SteamApps.PICSRequest>(), chunk.ToList());
            foreach (var result in info.Results ?? Enumerable.Empty<SteamApps.PICSProductInfoCallback>())
                foreach (var package in result.Packages.Values)
                    foreach (var child in package.KeyValues["appids"].Children)
                        owned.Add(child.AsUnsignedInteger());
        }
        return owned;
    }

    /// PICS product info for a set of apps, keyed by appid. Access tokens are
    /// fetched first because most non-public app info is gated behind one.
    static async Task<Dictionary<uint, SteamApps.PICSProductInfoCallback.PICSProductInfo>> RequestAppInfo(
        SteamApps apps, IEnumerable<uint> appIds)
    {
        var ids = appIds.Distinct().ToList();
        var found = new Dictionary<uint, SteamApps.PICSProductInfoCallback.PICSProductInfo>();
        if (ids.Count == 0) return found;

        var tokens = await apps.PICSGetAccessTokens(ids, new List<uint>());
        var requests = ids.Select(id =>
        {
            var req = new SteamKit2.SteamApps.PICSRequest(id);
            if (tokens.AppTokens.TryGetValue(id, out var token)) req.AccessToken = token;
            return req;
        }).ToList();

        foreach (var chunk in requests.Chunk(200))
        {
            var info = await apps.PICSGetProductInfo(chunk.ToList(), new List<SteamKit2.SteamApps.PICSRequest>());
            foreach (var result in info.Results ?? Enumerable.Empty<SteamApps.PICSProductInfoCallback>())
                foreach (var app in result.Apps.Values)
                    found[app.ID] = app;
        }
        return found;
    }

    /// True when the app owns at least one depot with a manifest that a Windows
    /// install would actually pull down.
    static bool HasInstallableDepots(SteamApps.PICSProductInfoCallback.PICSProductInfo info)
    {
        foreach (var depot in info.KeyValues["depots"].Children)
        {
            if (!uint.TryParse(depot.Name, out _)) continue;      // "branches", "baselanguages", …
            if (depot["manifests"] == KeyValue.Invalid) continue; // nothing to download

            var oslist = depot["config"]["oslist"];
            if (oslist != KeyValue.Invalid && !string.IsNullOrWhiteSpace(oslist.Value)
                && !oslist.Value.Split(',').Contains("windows"))
                continue;

            return true;
        }
        return false;
    }

    static async Task Enumerate(SteamSession s, uint appid)
    {
        var files = new List<object>();
        uint startIndex = 0;
        int page = 0;
        while (true)
        {
            page++;
            Console.Error.WriteLine($"enumerate: requesting page {page} (start_index={startIndex})");
            var job = s.Cloud.EnumerateUserFiles(new CCloud_EnumerateUserFiles_Request
            {
                appid = appid,
                extended_details = true,
                count = 500,
                start_index = startIndex,
            });
            // A unified-message job that never completes must not hang this
            // command forever with nothing on stdout to explain why. AsyncJob
            // isn't itself a Task, so wrap it to race against a timeout.
            var respTask = Task.Run(async () => await job);
            var timeout = Task.Delay(TimeSpan.FromSeconds(30));
            if (await Task.WhenAny(respTask, timeout) == timeout)
                throw new Exception($"enumerate page {page}: timed out waiting for Steam's response");
            var resp = await respTask;
            Console.Error.WriteLine(
                $"enumerate: page {page} result={resp.Result} files={resp.Body?.files?.Count.ToString() ?? "null"} " +
                $"total_files={resp.Body?.total_files.ToString() ?? "null"}");
            if (resp.Result != EResult.OK)
                throw new Exception($"EnumerateUserFiles failed: {resp.Result}");
            foreach (var f in resp.Body.files)
            {
                files.Add(new Dictionary<string, object?>
                {
                    ["filename"] = f.filename,
                    ["size"] = f.file_size,
                    ["timestamp"] = f.timestamp,
                    ["sha"] = f.file_sha,
                    ["ugcid"] = f.ugcid.ToString(),
                });
            }
            startIndex += (uint)resp.Body.files.Count;
            if (resp.Body.files.Count == 0 || startIndex >= resp.Body.total_files) break;
        }
        Console.Error.WriteLine($"enumerate: {files.Count} files total, serializing…");
        var json = JsonSerializer.Serialize(new Dictionary<string, object?> { ["files"] = files });
        Console.Error.WriteLine($"enumerate: serialized {json.Length} chars, writing…");
        lock (JsonOutputLock)
        {
            Console.WriteLine(json);
            Console.Out.Flush();
        }
        Console.Error.WriteLine("enumerate: emitted.");
    }

    // Process many downloads/uploads in ONE logged-on session. Spawning a fresh
    // process (= fresh Steam logon) per file gets the account throttled by the
    // CM after ~100 logons; batching keeps it to a single logon per sync. File
    // transfers are bounded so high-file-count games do not pay every Steam +
    // HTTP round trip serially, without flooding the service.
    static async Task Batch(SteamSession s, uint appid, string jobsPath)
    {
        using var doc = JsonDocument.Parse(await File.ReadAllTextAsync(jobsPath));
        var root = doc.RootElement;
        int downloaded = 0, uploaded = 0, failed = 0;
        using var http = NewHttpClient();

        if (root.TryGetProperty("downloads", out var dls))
        {
            var jobs = dls.EnumerateArray()
                .Select(d => (
                    Filename: d.GetProperty("filename").GetString()!,
                    OutputPath: d.GetProperty("out").GetString()!))
                .ToList();
            await RunTransfers(jobs, async d =>
            {
                try
                {
                    await DownloadCore(s, appid, d.Filename, d.OutputPath, http);
                    Interlocked.Increment(ref downloaded);
                    EmitJson(new Dictionary<string, object?> { ["op"] = "download", ["filename"] = d.Filename, ["ok"] = true });
                }
                catch (Exception ex)
                {
                    Interlocked.Increment(ref failed);
                    EmitJson(new Dictionary<string, object?> { ["op"] = "download", ["filename"] = d.Filename, ["error"] = ex.Message });
                }
            });
        }

        if (root.TryGetProperty("uploads", out var uls))
        {
            var jobs = uls.EnumerateArray()
                .Select(u => (
                    Filename: u.GetProperty("filename").GetString()!,
                    InputPath: u.GetProperty("in").GetString()!,
                    MTime: u.GetProperty("mtime").GetInt64()))
                .ToList();
            await RunTransfers(jobs, async u =>
            {
                try
                {
                    await UploadCore(s, appid, u.Filename, u.InputPath, u.MTime, http);
                    Interlocked.Increment(ref uploaded);
                    EmitJson(new Dictionary<string, object?> { ["op"] = "upload", ["filename"] = u.Filename, ["ok"] = true });
                }
                catch (Exception ex)
                {
                    Interlocked.Increment(ref failed);
                    EmitJson(new Dictionary<string, object?> { ["op"] = "upload", ["filename"] = u.Filename, ["error"] = ex.Message });
                }
            });
        }

        EmitJson(new Dictionary<string, object?> { ["summary"] = true, ["downloaded"] = downloaded, ["uploaded"] = uploaded, ["failed"] = failed });
    }

    const int MaxConcurrentTransfers = 4;

    static async Task RunTransfers<T>(IEnumerable<T> jobs, Func<T, Task> transfer)
    {
        using var gate = new SemaphoreSlim(MaxConcurrentTransfers);
        var tasks = jobs.Select(async job =>
        {
            await gate.WaitAsync();
            try { await transfer(job); }
            finally { gate.Release(); }
        });
        await Task.WhenAll(tasks);
    }

    static async Task DownloadCore(SteamSession s, uint appid, string filename, string outPath)
    {
        using var http = NewHttpClient();
        await DownloadCore(s, appid, filename, outPath, http);
    }

    static async Task DownloadCore(SteamSession s, uint appid, string filename, string outPath, HttpClient http)
    {
        var job = s.Cloud.ClientFileDownload(new CCloud_ClientFileDownload_Request
        {
            appid = appid,
            filename = filename,
            realm = 1,
        });
        var resp = await job;
        if (resp.Result != EResult.OK)
            throw new Exception($"ClientFileDownload failed: {resp.Result}");
        var body = resp.Body;
        if (body.is_explicit_delete)
            throw new Exception("Cloud reports this file as deleted.");
        if (body.encrypted)
            throw new Exception("Cloud returned an encrypted file; encrypted download is not supported.");

        var scheme = body.use_https ? "https" : "http";
        var url = $"{scheme}://{body.url_host}{body.url_path}";
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        foreach (var h in body.request_headers)
            req.Headers.TryAddWithoutValidation(h.name, h.value);

        using var httpResp = await http.SendAsync(req);
        httpResp.EnsureSuccessStatusCode();
        var bytes = await httpResp.Content.ReadAsByteArrayAsync();

        if (body.file_size != 0 && bytes.Length != body.file_size)
            Console.Error.WriteLine($"warning: downloaded {bytes.Length} bytes, expected {body.file_size}");

        bytes = InflateCloudFile(bytes, body.file_size, body.raw_file_size, body.sha_file, filename);

        var dir = Path.GetDirectoryName(Path.GetFullPath(outPath));
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        await File.WriteAllBytesAsync(outPath, bytes);
        try { File.SetLastWriteTimeUtc(outPath, DateTimeOffset.FromUnixTimeSeconds((long)body.time_stamp).UtcDateTime); } catch { }
    }

    // Steam stores a cloud save wrapped: the transfer is a zip holding exactly
    // one entry, which the Steam client names "z". Writing that payload verbatim
    // hands the game a zip where it expects its own save format — Mewgenics,
    // whose saves are SQLite, refuses it with "file is not a database".
    //
    // The wrapper is identified by its shape, not by the size fields: Steam does
    // not reliably report raw_file_size on this response (it came back as 0 or as
    // the compressed size for real Mewgenics saves), so trusting those silently
    // passed the zip straight through. A save that is genuinely a zip is left
    // alone — it takes more than one entry, or an entry not named "z".
    //
    // Anything that doesn't add up throws rather than returning bytes: a save we
    // cannot verify must never reach the disk.
    static byte[] InflateCloudFile(byte[] payload, uint fileSize, uint rawFileSize, byte[]? sha, string filename)
    {
        if (payload.Length < 4 || payload[0] != 'P' || payload[1] != 'K' || payload[2] != 3 || payload[3] != 4)
            return payload;

        using var archive = new ZipArchive(new MemoryStream(payload), ZipArchiveMode.Read);
        if (archive.Entries.Count != 1 || archive.Entries[0].FullName != "z") return payload;

        using var raw = new MemoryStream();
        using (var entryStream = archive.Entries[0].Open())
            entryStream.CopyTo(raw);
        var data = raw.ToArray();

        // Cross-check against raw_file_size only when Steam actually reported a
        // distinct one, and verify integrity against whichever form the SHA1
        // covers — it describes the stored blob for some files, the raw file for
        // others, and either one proves the transfer arrived intact.
        if (rawFileSize != 0 && rawFileSize != fileSize && data.Length != rawFileSize)
            throw new Exception($"{filename}: decompressed to {data.Length} bytes, expected {rawFileSize}.");
        if (sha != null && sha.Length > 0
            && !SHA1.HashData(data).SequenceEqual(sha)
            && !SHA1.HashData(payload).SequenceEqual(sha))
            throw new Exception($"{filename}: contents match neither the cloud SHA1 of the file nor of the transfer.");

        Console.Error.WriteLine(
            $"{filename}: unwrapped Steam's zip, {payload.Length} -> {data.Length} bytes " +
            $"(file_size={fileSize}, raw_file_size={rawFileSize})");
        return data;
    }

    static async Task UploadCore(SteamSession s, uint appid, string filename, string inPath, long mtime)
    {
        using var http = NewHttpClient();
        await UploadCore(s, appid, filename, inPath, mtime, http);
    }

    static async Task UploadCore(SteamSession s, uint appid, string filename, string inPath, long mtime, HttpClient http)
    {
        var data = await File.ReadAllBytesAsync(inPath);
        var sha1 = SHA1.HashData(data); // Steam keys cloud files by SHA1 of contents.

        var begin = await s.Cloud.ClientBeginFileUpload(new CCloud_ClientBeginFileUpload_Request
        {
            appid = appid,
            file_size = (uint)data.Length,
            raw_file_size = (uint)data.Length,
            file_sha = sha1,
            time_stamp = (ulong)mtime,
            filename = filename,
            can_encrypt = false,
            platforms_to_sync = 0xFFFFFFFF, // all platforms — so the Windows client sees it
        });
        if (begin.Result != EResult.OK)
            throw new Exception($"ClientBeginFileUpload failed: {begin.Result}");
        if (begin.Body.encrypt_file)
            throw new Exception("Steam requires an encrypted upload for this file; not supported. Aborting before any commit so nothing is corrupted.");

        foreach (var block in begin.Body.block_requests)
        {
            var scheme = block.use_https ? "https" : "http";
            var url = $"{scheme}://{block.url_host}{block.url_path}";
            var method = HttpMethodFor(block.http_method);

            byte[] payload = (block.explicit_body_data != null && block.explicit_body_data.Length > 0)
                ? block.explicit_body_data
                : data.Skip((int)block.block_offset).Take((int)block.block_length).ToArray();

            using var req = new HttpRequestMessage(method, url) { Content = new ByteArrayContent(payload) };
            foreach (var h in block.request_headers)
            {
                // Content-* headers must go on the content, not the request.
                if (h.name.StartsWith("Content-", StringComparison.OrdinalIgnoreCase))
                    req.Content.Headers.TryAddWithoutValidation(h.name, h.value);
                else
                    req.Headers.TryAddWithoutValidation(h.name, h.value);
            }

            using var blockResp = await http.SendAsync(req);
            if (!blockResp.IsSuccessStatusCode)
            {
                // Tell Steam the transfer failed so it doesn't leave a half-committed file.
                await Commit(s, appid, sha1, filename, succeeded: false);
                throw new Exception($"Block upload failed: HTTP {(int)blockResp.StatusCode} {url}");
            }
        }

        var commit = await Commit(s, appid, sha1, filename, succeeded: true);
        if (commit.Result != EResult.OK)
            throw new Exception($"ClientCommitFileUpload failed: {commit.Result}");
    }

    static async Task<SteamUnifiedMessages.ServiceMethodResponse<CCloud_ClientCommitFileUpload_Response>>
        Commit(SteamSession s, uint appid, byte[] sha1, string filename, bool succeeded)
    {
        return await s.Cloud.ClientCommitFileUpload(new CCloud_ClientCommitFileUpload_Request
        {
            transfer_succeeded = succeeded,
            appid = appid,
            file_sha = sha1,
            filename = filename,
        });
    }

    // MARK: - Helpers

    static HttpMethod HttpMethodFor(int eHttpMethod) => eHttpMethod switch
    {
        // EHTTPMethod: 1=GET 2=HEAD 3=POST 4=PUT 5=DELETE ...
        3 => HttpMethod.Post,
        4 => HttpMethod.Put,
        _ => HttpMethod.Put, // cloud block uploads are PUT in practice
    };

    static HttpClient NewHttpClient()
    {
        var c = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        c.DefaultRequestHeaders.UserAgent.ParseAdd("Valve/Steam HTTP Client 1.0");
        return c;
    }

    static string ReadToken(Dictionary<string, string> args)
    {
        if (args.TryGetValue("token-file", out var path)) return File.ReadAllText(path).Trim();
        if (args.TryGetValue("token", out var tok)) return tok.Trim();
        throw new Exception("missing --token-file or --token");
    }

    static string Require(Dictionary<string, string> args, string key)
        => args.TryGetValue(key, out var v) ? v : throw new Exception($"missing --{key}");

    static Dictionary<string, string> ParseArgs(string[] a)
    {
        var d = new Dictionary<string, string>();
        for (int i = 0; i < a.Length; i++)
        {
            if (i == 0 && !a[i].StartsWith("--")) { d["_cmd"] = a[i]; continue; }
            if (a[i].StartsWith("--"))
            {
                var key = a[i].Substring(2);
                var val = (i + 1 < a.Length && !a[i + 1].StartsWith("--")) ? a[++i] : "true";
                d[key] = val;
            }
        }
        return d;
    }

    static readonly object JsonOutputLock = new();

    static void EmitJson(object o)
    {
        // Serialize outside the lock/try-free path so a failure here (rather
        // than in the write itself) is distinguishable in the trace, and
        // flush explicitly rather than trusting Console.Out's autoflush —
        // belt-and-suspenders for a helper whose final line has gone missing
        // for reasons still being tracked down.
        var json = JsonSerializer.Serialize(o);
        lock (JsonOutputLock)
        {
            Console.WriteLine(json);
            Console.Out.Flush();
        }
    }
}

// Owns a logged-on SteamClient + the Cloud unified service. Pumps callbacks on
// a background thread for the lifetime of the session.
sealed class SteamSession : IDisposable
{
    // Instrumentation. A session that quietly stops receiving callbacks looks
    // identical to a healthy idle one, so these make the difference visible.
    public static long PumpIterations;
    public static long PumpFaults;
    public static long CallbacksSeen;

    public SteamClient Client { get; }
    public Cloud Cloud { get; private set; } = null!;
    public SteamUnifiedMessages Unified { get; private set; } = null!;
    readonly CallbackManager _cb;
    readonly CancellationTokenSource _pump = new();
    readonly TaskCompletionSource<List<SteamApps.LicenseListCallback.License>> _licenses =
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    /// The account's package licences, which Steam pushes shortly after logon.
    /// Ownership of a DLC can only be derived from these, so callers wait for
    /// the push rather than racing it.
    public async Task<List<SteamApps.LicenseListCallback.License>> LicensesAsync()
    {
        var timeout = Task.Delay(TimeSpan.FromSeconds(30));
        if (await Task.WhenAny(_licenses.Task, timeout) == timeout)
            throw new Exception("timed out waiting for Steam to send the account's licenses");
        return await _licenses.Task;
    }

    SteamSession(SteamClient client, CallbackManager cb)
    {
        Client = client; _cb = cb;
    }

    /// Subscribe to a Steam callback for the life of this session.
    public void Subscribe<T>(Action<T> handler) where T : CallbackMsg
        => _cb.Subscribe(handler);

    static SteamSession StartPump()
    {
        var client = new SteamClient();
        var cb = new CallbackManager(client);
        var session = new SteamSession(client, cb);
        var token = session._pump.Token;
        _ = Task.Run(() =>
        {
            try
            {
            while (!token.IsCancellationRequested)
            {
                // A throwing handler must never take the pump down with it.
                // Unguarded, one bad callback silently ends callback delivery
                // for the rest of the session: the connection still looks alive
                // and commands still appear to work, but nothing Steam sends
                // back — persona updates, disconnects, logoff reasons — is ever
                // seen again. Short-lived commands got away with it; a session
                // that runs for hours does not.
                try
                {
                    cb.RunWaitCallbacks(TimeSpan.FromMilliseconds(200));
                    Interlocked.Increment(ref PumpIterations);
                }
                catch (Exception ex)
                {
                    Interlocked.Increment(ref PumpFaults);
                    try { Console.Error.WriteLine($"callback handler threw: {ex}"); } catch { }
                }
            }
            }
            finally { Console.Error.WriteLine($"callback pump stopped after {PumpIterations} iterations."); }
        });
        return session;
    }

    /// Connect to a CM server without logging on (used by the QR auth flow,
    /// which establishes its own session via the authentication service).
    public static async Task<SteamSession> ConnectOnlyAsync()
    {
        var session = StartPump();
        var connected = new TaskCompletionSource();
        session._cb.Subscribe<SteamClient.ConnectedCallback>(_ => connected.TrySetResult());
        session._cb.Subscribe<SteamClient.DisconnectedCallback>(_ =>
        {
            if (!connected.Task.IsCompleted) connected.TrySetException(new Exception("disconnected before connect"));
        });
        session.Client.Connect();
        var timeout = Task.Delay(TimeSpan.FromSeconds(45));
        if (await Task.WhenAny(connected.Task, timeout) == timeout)
            throw new Exception("timed out connecting to Steam");
        await connected.Task;
        Console.Error.WriteLine("connected (no logon).");
        return session;
    }

    /// Connect and log on with a SteamClient-audience refresh token, then bind
    /// the Cloud unified service.
    // Steam tells concurrent sessions on one account apart by LoginID. Left
    // unset they all collide on the same default — so every new logon evicts
    // the last with LogonSessionReplaced. That includes our own short-lived
    // commands evicting the long-lived presence session, and the user's real
    // Steam client evicting both.
    //
    // The presence session gets a fixed id so its own reconnects keep one
    // identity; every other command gets a random one, so a library refresh or
    // a cloud sync can't knock presence offline mid-game.
    public const uint PresenceLoginID = 0x42454552; // "BEER"
    public static readonly uint CommandLoginID = (uint)Random.Shared.Next(1, int.MaxValue);

    /// Log on, retrying a connection that drops before the logon completes.
    ///
    /// Steam's CMs drop connections routinely — especially after a burst of
    /// logons, which is exactly what a game crashing and being relaunched
    /// produces. Treating the first drop as fatal turns one transient refusal
    /// into a dead presence session and a failed library refresh at the same
    /// moment.
    ///
    /// A refusal Steam actually explains (bad token, rate limit) is NOT retried:
    /// re-attempting those only deepens the cooldown.
    public static async Task<SteamSession> LogOnAsync(string account, string refreshToken, uint loginID)
    {
        Exception? last = null;
        for (var attempt = 1; attempt <= 4; attempt++)
        {
            try
            {
                return await LogOnOnceAsync(account, refreshToken, loginID);
            }
            catch (LogonFailedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                last = ex;
                Console.Error.WriteLine($"logon attempt {attempt}/4 failed: {ex.Message}");
                if (attempt < 4)
                    await Task.Delay(TimeSpan.FromSeconds(Math.Pow(2, attempt)));
            }
        }
        throw last!;
    }

    static async Task<SteamSession> LogOnOnceAsync(string account, string refreshToken, uint loginID)
    {
        var session = StartPump();
        var user = session.Client.GetHandler<SteamUser>()!;
        var unified = session.Client.GetHandler<SteamUnifiedMessages>()!;
        // RunContinuationsAsynchronously is load-bearing, not a style choice.
        // Without it, TrySetResult below runs everything awaiting this task
        // inline on the callback pump thread — so the command itself ends up
        // executing there. A command that suspends gives the thread back; one
        // that parks on a blocking read never does, and the pump stops
        // dispatching for good: no disconnects, no reconnect logons, no persona
        // updates, while the process looks perfectly healthy.
        var loggedOn = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);

        session._cb.Subscribe<SteamClient.ConnectedCallback>(_ =>
        {
            Console.Error.WriteLine("connected; logging on…");
            user.LogOn(new SteamUser.LogOnDetails
            {
                Username = account,
                AccessToken = refreshToken,
                ShouldRememberPassword = true,
                LoginID = loginID,
            });
        });
        session._cb.Subscribe<SteamClient.DisconnectedCallback>(_ =>
        {
            if (!loggedOn.Task.IsCompleted)
                loggedOn.TrySetException(new Exception("disconnected before logon completed"));
            session._licenses.TrySetException(new Exception("disconnected before licenses arrived"));
        });
        session._cb.Subscribe<SteamApps.LicenseListCallback>(l =>
        {
            if (l.Result == EResult.OK)
                session._licenses.TrySetResult(l.LicenseList.ToList());
            else
                session._licenses.TrySetException(new Exception($"license list failed: {l.Result}"));
        });
        session._cb.Subscribe<SteamUser.LoggedOnCallback>(l =>
        {
            if (l.Result == EResult.OK) loggedOn.TrySetResult();
            else loggedOn.TrySetException(new LogonFailedException($"logon failed: {l.Result} / {l.ExtendedResult}", l.Result));
        });

        session.Unified = unified;
        session.Cloud = unified.CreateService<Cloud>();
        session.Client.Connect();

        try
        {
            var timeout = Task.Delay(TimeSpan.FromSeconds(45));
            if (await Task.WhenAny(loggedOn.Task, timeout) == timeout)
                throw new Exception("timed out connecting/logging on to Steam");
            await loggedOn.Task; // surface logon exception if any
        }
        catch
        {
            // Each attempt builds a fresh client and pump thread; a failed one
            // has to be torn down or a retry leaks both.
            session.Disconnect();
            session.Dispose();
            throw;
        }

        Console.Error.WriteLine("logged on.");
        return session;
    }

    public void Disconnect()
    {
        try { Client.GetHandler<SteamUser>()?.LogOff(); } catch { }
        try { Client.Disconnect(); } catch { }
    }

    public void Dispose() => _pump.Cancel();
}

// Thrown when a Steam logon fails. Carries the EResult so the app can tell a
// genuine credential failure (needs a fresh QR sign-in) apart from a transient
// throttle (just wait and retry — re-auth would only burn more logons).
sealed class LogonFailedException : Exception
{
    public EResult Result { get; }
    public LogonFailedException(string message, EResult result) : base(message) { Result = result; }

    // Steam temporarily refused the logon (too many recent logins, CM busy…).
    public bool IsRateLimited => Result is EResult.RateLimitExceeded
        or EResult.AccountLoginDeniedThrottle
        or EResult.TryAnotherCM
        or EResult.ServiceUnavailable
        or EResult.Busy;
}

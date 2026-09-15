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
//   playing   --appid N --steamid S   (holds the session until stdin closes)
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

            using var session = await SteamSession.LogOnAsync(account, token);
            try
            {
                switch (cmd)
                {
                    case "ownedgames": await OwnedGames(session, ulong.Parse(Require(args, "steamid"))); break;
                    case "dlc": await Dlc(session, appid); break;
                    case "playing":
                        await Playing(session, appid, ulong.Parse(Require(args, "steamid")));
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

    // Hold a logged-on session for the length of a play session so Steam
    // records the hours, then retract.
    //
    // The session ends at stdin EOF. BEER holds the write end of that pipe, so
    // EOF arrives when the game exits *and* if BEER itself dies by any means,
    // including SIGKILL — macOS has no parent-death signal, and this is the
    // only teardown that survives a force quit. Without it a crashed BEER would
    // leave the account showing as in-game indefinitely.
    static async Task Playing(SteamSession s, uint appid, ulong steamid)
    {
        if (appid == 0) throw new Exception("playing requires --appid");

        var friends = s.Client.GetHandler<SteamFriends>()!;

        // Report what Steam actually believes this persona is doing, and every
        // later change to it. If the game shows up and is then reset to 0,
        // another session on the account is overwriting us: games-played is
        // last-writer-wins, and the real Steam client broadcasts its own empty
        // list. `session_instances` says how many sessions are logged on.
        uint lastReported = uint.MaxValue;
        s.Subscribe<SteamFriends.PersonaStateCallback>(cb =>
        {
            if (s.Client.SteamID is null || cb.FriendID != s.Client.SteamID) return;
            if (cb.GameAppID == lastReported) return;
            lastReported = cb.GameAppID;
            EmitJson(new Dictionary<string, object?>
            {
                ["presence_appid"] = cb.GameAppID,
                ["presence_name"] = cb.GameName,
                ["persona_state"] = cb.State.ToString(),
                ["session_instances"] = cb.OnlineSessionInstances,
            });
        });

        // A fresh SteamKit logon's persona starts Offline, and Steam does not
        // broadcast a game for an offline persona — so this has to happen
        // before the announcement or nobody ever sees it. Harmless when the
        // account is already online elsewhere.
        friends.SetPersonaState(EPersonaState.Online);

        Announce(s, appid);
        // Swift waits for this line before deleting the token file, and treats
        // it as the point the session is actually live.
        EmitJson(new Dictionary<string, object?> { ["playing"] = appid });

        // Wait for EOF, but notice a dropped connection rather than sitting on
        // a dead socket believing we are still being counted.
        var closed = Console.In.ReadToEndAsync();
        while (!closed.IsCompleted)
        {
            await Task.WhenAny(closed, Task.Delay(TimeSpan.FromSeconds(5)));
            if (!closed.IsCompleted && s.Client.IsConnected && s.Client.SteamID is { } me)
            {
                // Re-assert: another session's games-played can overwrite ours
                // at any point, and re-sending is how the real client keeps its
                // own status stuck. Also refreshes the diagnostic above.
                Announce(s, appid);
                friends.RequestFriendInfo(me,
                    EClientPersonaStateFlag.Status
                    | EClientPersonaStateFlag.GameExtraInfo
                    | EClientPersonaStateFlag.Presence);
            }
            if (!closed.IsCompleted && !s.Client.IsConnected)
            {
                EmitJson(new Dictionary<string, object?>
                {
                    ["disconnected"] = true,
                    ["error"] = "Steam connection dropped during play; time after this point was not recorded.",
                });
                return;
            }
        }

        Announce(s, 0);
        // Give the retraction time to reach the CM before the caller's finally
        // block disconnects the socket underneath it, and to let Steam credit
        // the session it just ended.
        await Task.Delay(TimeSpan.FromSeconds(2));

        // Report the new total on the logon we already hold, rather than making
        // the app spend a second one re-reading the whole library for one
        // number. A stale read here costs nothing: the app refuses to move the
        // counter backwards, and the next library refresh corrects it.
        long? playtime = null;
        try
        {
            playtime = await PlaytimeMinutes(s, steamid, appid);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"could not re-read play time: {ex.Message}");
        }

        EmitJson(new Dictionary<string, object?>
        {
            ["stopped"] = appid,
            ["playtime_forever"] = playtime,
        });
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
        while (true)
        {
            var job = s.Cloud.EnumerateUserFiles(new CCloud_EnumerateUserFiles_Request
            {
                appid = appid,
                extended_details = true,
                count = 500,
                start_index = startIndex,
            });
            var resp = await job;
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
        EmitJson(new Dictionary<string, object?> { ["files"] = files });
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

        var dir = Path.GetDirectoryName(Path.GetFullPath(outPath));
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        await File.WriteAllBytesAsync(outPath, bytes);
        try { File.SetLastWriteTimeUtc(outPath, DateTimeOffset.FromUnixTimeSeconds((long)body.time_stamp).UtcDateTime); } catch { }
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
        lock (JsonOutputLock)
            Console.WriteLine(JsonSerializer.Serialize(o));
    }
}

// Owns a logged-on SteamClient + the Cloud unified service. Pumps callbacks on
// a background thread for the lifetime of the session.
sealed class SteamSession : IDisposable
{
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
            while (!token.IsCancellationRequested)
                cb.RunWaitCallbacks(TimeSpan.FromMilliseconds(200));
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
    public static async Task<SteamSession> LogOnAsync(string account, string refreshToken)
    {
        var session = StartPump();
        var user = session.Client.GetHandler<SteamUser>()!;
        var unified = session.Client.GetHandler<SteamUnifiedMessages>()!;
        var loggedOn = new TaskCompletionSource();

        session._cb.Subscribe<SteamClient.ConnectedCallback>(_ =>
        {
            Console.Error.WriteLine("connected; logging on…");
            user.LogOn(new SteamUser.LogOnDetails
            {
                Username = account,
                AccessToken = refreshToken,
                ShouldRememberPassword = true,
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

        var timeout = Task.Delay(TimeSpan.FromSeconds(45));
        if (await Task.WhenAny(loggedOn.Task, timeout) == timeout)
            throw new Exception("timed out connecting/logging on to Steam");
        await loggedOn.Task; // surface logon exception if any

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

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
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
// same token GameNative already obtains via QR sign-in. This unlocks PUSH,
// which the web-scrape path could never do.
//
// All commands print a single JSON object to stdout. Human/log noise goes to
// stderr. Exit code 0 = ok, non-zero = failure (with {"error":...} on stdout).
//
// Commands:
//   enumerate --appid N
//   download  --appid N --file "<ufs filename>" --out <localPath>
//   upload    --appid N --file "<ufs filename>" --in <localPath> [--mtime <unix>]
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
            Console.Error.WriteLine("usage: CloudSync <enumerate|download|upload> --token-file F --account NAME --appid N [...]");
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

            var token = ReadToken(args);
            var account = Require(args, "account");
            uint appid = args.TryGetValue("appid", out var aid) ? uint.Parse(aid) : 0; // not needed by ownedgames

            using var session = await SteamSession.LogOnAsync(account, token);
            try
            {
                switch (cmd)
                {
                    case "ownedgames": await OwnedGames(session, ulong.Parse(Require(args, "steamid"))); break;
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

    // QR sign-in that yields a SteamClient-audience refresh token (the kind the
    // Cloud client protocol accepts). Emits the challenge URL as JSON so the
    // Swift UI can render the QR, re-emits on rotation, then emits the token.
    static async Task Auth()
    {
        using var session = await SteamSession.ConnectOnlyAsync();

        var authSession = await session.Client.Authentication.BeginAuthSessionViaQRAsync(new AuthSessionDetails
        {
            PlatformType = EAuthTokenPlatformType.k_EAuthTokenPlatformType_SteamClient,
            DeviceFriendlyName = "GameNative for Mac",
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
    // CM after ~100 logons; batching keeps it to a single logon per sync.
    static async Task Batch(SteamSession s, uint appid, string jobsPath)
    {
        using var doc = JsonDocument.Parse(await File.ReadAllTextAsync(jobsPath));
        var root = doc.RootElement;
        int downloaded = 0, uploaded = 0, failed = 0;

        if (root.TryGetProperty("downloads", out var dls))
        {
            foreach (var d in dls.EnumerateArray())
            {
                var filename = d.GetProperty("filename").GetString()!;
                var outp = d.GetProperty("out").GetString()!;
                try
                {
                    await DownloadCore(s, appid, filename, outp);
                    downloaded++;
                    EmitJson(new Dictionary<string, object?> { ["op"] = "download", ["filename"] = filename, ["ok"] = true });
                }
                catch (Exception ex)
                {
                    failed++;
                    EmitJson(new Dictionary<string, object?> { ["op"] = "download", ["filename"] = filename, ["error"] = ex.Message });
                }
            }
        }

        if (root.TryGetProperty("uploads", out var uls))
        {
            foreach (var u in uls.EnumerateArray())
            {
                var filename = u.GetProperty("filename").GetString()!;
                var inp = u.GetProperty("in").GetString()!;
                var mtime = u.GetProperty("mtime").GetInt64();
                try
                {
                    await UploadCore(s, appid, filename, inp, mtime);
                    uploaded++;
                    EmitJson(new Dictionary<string, object?> { ["op"] = "upload", ["filename"] = filename, ["ok"] = true });
                }
                catch (Exception ex)
                {
                    failed++;
                    EmitJson(new Dictionary<string, object?> { ["op"] = "upload", ["filename"] = filename, ["error"] = ex.Message });
                }
            }
        }

        EmitJson(new Dictionary<string, object?> { ["summary"] = true, ["downloaded"] = downloaded, ["uploaded"] = uploaded, ["failed"] = failed });
    }

    static async Task DownloadCore(SteamSession s, uint appid, string filename, string outPath)
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

        using var http = NewHttpClient();
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

        using var http = NewHttpClient();
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

    static void EmitJson(object o)
        => Console.WriteLine(JsonSerializer.Serialize(o));
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

    SteamSession(SteamClient client, CallbackManager cb)
    {
        Client = client; _cb = cb;
    }

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

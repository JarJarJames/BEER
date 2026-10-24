using CloudSync.Cli;
using CloudSync.Commands;
using CloudSync.Commands.Presence;
using CloudSync.Steam;
using CloudSync.Transfers;

namespace CloudSync;

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
//   achievements-get   --appid N --steamid S
//   achievements-store --appid N --steamid S --unlocks <path to JSON array of names>
//   prepare-depot-auth --depot-executable <path>
//
// Auth (all commands): --token <refreshToken> --account <name>
//   Prefer --token-file <path> so the token never appears in argv / ps output.

static class Program
{
    internal static async Task<int> Main(string[] rawArgs)
    {
        var args = CliArgs.Parse(rawArgs);
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
                await AuthCommand.RunAsync();
                return 0;
            }

            // DepotDownloader has no CLI flag for an existing SteamClient
            // refresh token. Bridge BEER's Keychain-owned token into its
            // account cache; Swift removes this file as soon as the process
            // exits and records its path for crash cleanup.
            if (cmd == "prepare-depot-auth")
            {
                var bridgeToken = CliArgs.ReadToken(args);
                var bridgeAccount = CliArgs.Require(args, "account");
                var config = DepotAuthCommand.Prepare(
                    CliArgs.Require(args, "depot-executable"), bridgeAccount, bridgeToken);
                JsonOutput.Emit(new Dictionary<string, object?>
                {
                    ["prepared"] = true,
                    ["config_path"] = config,
                });
                return 0;
            }

            var token = CliArgs.ReadToken(args);
            var account = CliArgs.Require(args, "account");
            uint appid = args.TryGetValue("appid", out var aid) ? uint.Parse(aid) : 0; // not needed by ownedgames

            using var session = await SteamSession.LogOnAsync(
                account, token,
                cmd == "presence" ? SteamSession.PresenceLoginID : SteamSession.CommandLoginID);
            try
            {
                switch (cmd)
                {
                    case "ownedgames": await OwnedGamesCommand.RunAsync(session, ulong.Parse(CliArgs.Require(args, "steamid"))); break;
                    case "dlc": await DlcCommand.RunAsync(session, appid); break;
                    case "presence":
                        await new PresenceSession(session, ulong.Parse(CliArgs.Require(args, "steamid"))).RunAsync();
                        break;
                    case "enumerate": await EnumerateCommand.RunAsync(session, appid); break;
                    case "batch": await BatchCommand.RunAsync(session, appid, CliArgs.Require(args, "jobs")); break;
                    case "achievements-get":
                        await AchievementsCommand.GetAsync(session, appid, ulong.Parse(CliArgs.Require(args, "steamid")));
                        break;
                    case "achievements-store":
                        await AchievementsCommand.StoreAsync(session, appid, ulong.Parse(CliArgs.Require(args, "steamid")), CliArgs.Require(args, "unlocks"));
                        break;
                    case "download":
                        await CloudTransfers.DownloadAsync(session, appid, CliArgs.Require(args, "file"), CliArgs.Require(args, "out"));
                        JsonOutput.Emit(new Dictionary<string, object?> { ["downloaded"] = true });
                        break;
                    case "upload":
                        long mtime = args.TryGetValue("mtime", out var mt) ? long.Parse(mt) : DateTimeOffset.UtcNow.ToUnixTimeSeconds();
                        await CloudTransfers.UploadAsync(session, appid, CliArgs.Require(args, "file"), CliArgs.Require(args, "in"), mtime);
                        JsonOutput.Emit(new Dictionary<string, object?> { ["uploaded"] = true });
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
            JsonOutput.Emit(payload);
            Console.Error.WriteLine(ex);
            return 1;
        }
    }
}

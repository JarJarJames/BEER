using CloudSync.Cli;
using CloudSync.Commands;
using CloudSync.Commands.Presence;
using CloudSync.Steam;

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
//   enumerate --appid N     (cloud files + ufs save-folder rules)
//   dlc       --appid N
//   launchinfo --appid N
//   installsize --appids N,N,...  (disk a Windows install of them needs; bytes or null)
//   clienticon --appid N    (hash of the app's Windows .ico, or null)
//   updatecheck --jobs <path to JSON [{appid, dir}]>  (current/update/untracked/unknown per installed game)
//   session                 (long-lived: one logon the app runs everything through;
//                            see PresenceSession for what it reads on stdin)
//   download  --appid N --file "<ufs filename>" --out <localPath>
//   upload    --appid N --file "<ufs filename>" --in <localPath> [--mtime <unix>]
//   achievements-get   --appid N --steamid S
//   achievements-store --appid N --steamid S --unlocks <path to JSON array of names>
//   prepare-depot-auth --depot-executable <path>
//
// Auth (all commands): --token <refreshToken> --account <name>
//   Prefer --token-file <path> so the token never appears in argv / ps output.
//
// The app keeps ONE `session` running and sends every other command to it as
// a request, so BEER is a single logon on the account. Run by hand, each
// command logs on for itself.

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

            using var session = await SteamSession.LogOnAsync(
                account, token,
                cmd == "session" ? SteamSession.SessionLoginID : SteamSession.CommandLoginID);
            try
            {
                if (cmd == "session")
                {
                    await new PresenceSession(session).RunAsync();
                }
                else if (!await CommandDispatch.RunAsync(session, cmd, args))
                {
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

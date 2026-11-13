using CloudSync.Cli;
using CloudSync.Steam;
using CloudSync.Transfers;

namespace CloudSync.Commands;

/// Every command that needs a logged-on session, run against one. The app sends
/// these as requests on its single `session`; run by hand, each gets its own
/// logon (see Program).
static class CommandDispatch
{
    /// False for a command this doesn't know.
    public static async Task<bool> RunAsync(SteamSession session, string cmd, Dictionary<string, string> args)
    {
        uint appid = args.TryGetValue("appid", out var aid) ? uint.Parse(aid) : 0;
        switch (cmd)
        {
            case "ownedgames": await OwnedGamesCommand.RunAsync(session, ulong.Parse(CliArgs.Require(args, "steamid"))); break;
            case "dlc": await DlcCommand.RunAsync(session, appid); break;
            case "launchinfo": await LaunchInfoCommand.RunAsync(session, appid); break;
            case "clienticon": await ClientIconCommand.RunAsync(session, appid); break;
            case "installsize":
                await InstallSizeCommand.RunAsync(session, CliArgs.Require(args, "appids")
                    .Split(',', StringSplitOptions.RemoveEmptyEntries).Select(uint.Parse).ToList());
                break;
            case "updatecheck": await UpdateCheckCommand.RunAsync(session, CliArgs.Require(args, "jobs")); break;
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
                return false;
        }
        return true;
    }

    /// Run one `session` request, tagging everything it emits with its id and
    /// ending with `{"id":…,"done":true}`. A failure is reported as that
    /// request's error; it never takes the session down.
    public static async Task ServeAsync(SteamSession session, long id, string cmd, Dictionary<string, string> args)
    {
        JsonOutput.RequestId.Value = id;
        try
        {
            if (!await RunAsync(session, cmd, args))
                JsonOutput.Emit(new Dictionary<string, object?> { ["error"] = $"unknown command: {cmd}" });
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"request {id} ({cmd}) failed: {ex}");
            JsonOutput.Emit(new Dictionary<string, object?> { ["error"] = ex.Message });
        }
        finally
        {
            JsonOutput.Emit(new Dictionary<string, object?> { ["done"] = true });
        }
    }
}

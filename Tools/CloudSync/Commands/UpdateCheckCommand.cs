using System.Text.Json;
using CloudSync.Cli;
using CloudSync.Steam;
using SteamKit2;

namespace CloudSync.Commands;

static class UpdateCheckCommand
{
    // Report whether each installed game has an update on Steam's public
    // branch: current, update, untracked (no DepotDownloader record in its
    // folder) or unknown. `jobsPath` is a JSON array of
    // {"appid": N, "dir": "<game folder>", "leftout": [depot ids]}, where
    // `leftout` (optional) is the DLC depots the player left out of the
    // download. One logon covers every game.
    //
    // A game Steam returns no app info for is `unknown`, not an error, so one
    // delisted game doesn't hide the rest.
    public static async Task RunAsync(SteamSession s, string jobsPath)
    {
        var jobs = ReadJobs(await File.ReadAllTextAsync(jobsPath));
        var apps = s.Client.GetHandler<SteamApps>()!;

        var licensedTask = OwnedApps.RequestLicensedAsync(s, apps);
        var info = await AppInfo.RequestAsync(apps, jobs.Select(j => j.AppId));
        // Depots that take their manifests from another app need that app's info.
        var otherIds = info.Values.OfType<SteamApps.PICSProductInfoCallback.PICSProductInfo>()
            .SelectMany(a => GameUpdate.OtherApps(a.KeyValues)).Distinct().ToList();
        var otherApps = (await AppInfo.RequestAsync(apps, otherIds))
            .Where(a => a.Value is not null).ToDictionary(a => a.Key, a => a.Value.KeyValues);
        var licensed = await licensedTask;

        var games = jobs.Select(job =>
        {
            var status = info.TryGetValue(job.AppId, out var app) && app is not null
                ? GameUpdate.Compare(app.KeyValues, licensed, InstalledDepots.Read(job.Dir), job.LeftOut, otherApps)
                : GameUpdateStatus.Unknown;
            return new Dictionary<string, object?>
            {
                ["appid"] = job.AppId,
                ["status"] = GameUpdate.Name(status),
            };
        }).ToList();

        JsonOutput.Emit(new Dictionary<string, object?> { ["games"] = games });
    }

    internal sealed record Job(uint AppId, string Dir, IReadOnlySet<uint> LeftOut);

    internal static List<Job> ReadJobs(string json)
    {
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.EnumerateArray()
            .Select(j => new Job(
                j.GetProperty("appid").GetUInt32(),
                j.GetProperty("dir").GetString() ?? "",
                j.TryGetProperty("leftout", out var leftOut)
                    ? leftOut.EnumerateArray().Select(d => d.GetUInt32()).ToHashSet()
                    : new HashSet<uint>()))
            .Where(j => j.AppId != 0 && j.Dir.Length > 0)
            .ToList();
    }
}

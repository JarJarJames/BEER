using CloudSync.Cli;
using CloudSync.Steam;
using SteamKit2;

namespace CloudSync.Commands;

static class InstallSizeCommand
{
    // Report how much disk a Windows install of `appids` needs together (a game,
    // or a batch of its DLC), counting the DLC content this account owns, so
    // the app can refuse a download the disk can't hold. `bytes` is null when
    // Steam lists no size for any of them. One logon covers the whole batch.
    //
    // Also lists what that download is made of, so the install sheet can leave
    // DLC out: `depots` is every depot it fetches, and `dlc` the owned DLC
    // among them, each with its own depots and size. `depotBytes` is each
    // depot's own size, for the download's progress bar.
    public static async Task RunAsync(SteamSession s, IReadOnlyList<uint> appids)
    {
        if (appids.Count == 0) throw new Exception("installsize requires --appids");
        var apps = s.Client.GetHandler<SteamApps>()!;

        var ownedTask = OwnedApps.RequestAsync(s, apps);
        var info = await AppInfo.RequestAsync(apps, appids);
        var owned = await ownedTask;

        var depots = new List<FetchedDepot>();
        foreach (var appid in appids)
        {
            if (!info.TryGetValue(appid, out var app) || app is null)
                throw new Exception($"Steam returned no app info for {appid}");
            depots.AddRange(InstallSize.Depots(app.KeyValues, owned));
        }

        var byDlc = depots.Where(d => d.DlcAppId is not null).GroupBy(d => d.DlcAppId!.Value).ToList();
        var dlcInfo = await AppInfo.RequestAsync(apps, byDlc.Select(g => g.Key));
        var dlc = byDlc.Select(g =>
        {
            dlcInfo.TryGetValue(g.Key, out var app);
            var name = app?.KeyValues["common"]["name"].AsString();
            return new Dictionary<string, object?>
            {
                ["appid"] = g.Key,
                ["name"] = string.IsNullOrWhiteSpace(name) ? $"DLC {g.Key}" : name,
                ["bytes"] = InstallSize.Total(g),
                ["depots"] = g.Select(d => d.Id).ToList(),
            };
        }).ToList();

        JsonOutput.Emit(new Dictionary<string, object?>
        {
            ["bytes"] = InstallSize.Total(depots),
            ["depots"] = depots.Select(d => d.Id).ToList(),
            ["depotBytes"] = InstallSize.BytesByDepot(depots),
            ["dlc"] = dlc,
        });
    }
}

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
    public static async Task RunAsync(SteamSession s, IReadOnlyList<uint> appids)
    {
        if (appids.Count == 0) throw new Exception("installsize requires --appids");
        var apps = s.Client.GetHandler<SteamApps>()!;

        var ownedTask = OwnedApps.RequestAsync(s, apps);
        var info = await AppInfo.RequestAsync(apps, appids);
        var owned = await ownedTask;

        ulong total = 0;
        var found = false;
        foreach (var appid in appids)
        {
            if (!info.TryGetValue(appid, out var app) || app is null)
                throw new Exception($"Steam returned no app info for {appid}");
            if (InstallSize.Estimate(app.KeyValues, owned) is not { } bytes) continue;
            total += bytes;
            found = true;
        }
        JsonOutput.Emit(new Dictionary<string, object?> { ["bytes"] = found ? total : null });
    }
}

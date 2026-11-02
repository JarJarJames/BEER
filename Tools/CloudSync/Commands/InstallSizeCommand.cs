using CloudSync.Cli;
using CloudSync.Steam;
using SteamKit2;

namespace CloudSync.Commands;

static class InstallSizeCommand
{
    // Report how much disk a Windows install of `appid` needs, so the app can
    // refuse to start a download the disk can't hold. `bytes` is null when
    // Steam lists no size.
    public static async Task RunAsync(SteamSession s, uint appid)
    {
        if (appid == 0) throw new Exception("installsize requires --appid");
        var apps = s.Client.GetHandler<SteamApps>()!;

        var info = await AppInfo.RequestAsync(apps, new[] { appid });
        if (!info.TryGetValue(appid, out var app) || app is null)
            throw new Exception($"Steam returned no app info for {appid}");

        JsonOutput.Emit(new Dictionary<string, object?> { ["bytes"] = InstallSize.Estimate(app.KeyValues) });
    }
}

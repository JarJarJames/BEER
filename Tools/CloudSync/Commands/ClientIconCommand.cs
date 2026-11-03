using CloudSync.Cli;
using CloudSync.Steam;
using SteamKit2;

namespace CloudSync.Commands;

static class ClientIconCommand
{
    // Report the hash of `appid`'s Windows icon, so the app can offer it for
    // shortcuts. `clienticon` is null when Steam lists none.
    public static async Task RunAsync(SteamSession s, uint appid)
    {
        if (appid == 0) throw new Exception("clienticon requires --appid");
        var apps = s.Client.GetHandler<SteamApps>()!;

        var info = await AppInfo.RequestAsync(apps, new[] { appid });
        if (!info.TryGetValue(appid, out var app) || app is null)
            throw new Exception($"Steam returned no app info for {appid}");

        JsonOutput.Emit(new Dictionary<string, object?> { ["clienticon"] = ClientIcon.Hash(app.KeyValues) });
    }
}

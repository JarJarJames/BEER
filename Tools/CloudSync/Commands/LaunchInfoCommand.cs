using CloudSync.Cli;
using CloudSync.Launch;
using CloudSync.Steam;
using SteamKit2;

namespace CloudSync.Commands;

static class LaunchInfoCommand
{
    // Report the Windows launch options Steam lists for `appid`, best first, so
    // the app launches the game rather than a bundled tool or launcher.
    public static async Task RunAsync(SteamSession s, uint appid)
    {
        if (appid == 0) throw new Exception("launchinfo requires --appid");
        var apps = s.Client.GetHandler<SteamApps>()!;

        var info = await AppInfo.RequestAsync(apps, new[] { appid });
        if (!info.TryGetValue(appid, out var app) || app is null)
            throw new Exception($"Steam returned no app info for {appid}");

        var launch = LaunchConfigPicker.Pick(app.KeyValues).Select(e => new Dictionary<string, object?>
        {
            ["executable"] = e.Executable,
            ["arguments"] = e.Arguments,
            ["workingdir"] = e.WorkingDir,
            ["type"] = e.Type,
            ["description"] = e.Description,
        });
        JsonOutput.Emit(new Dictionary<string, object?> { ["launch"] = launch.ToList() });
    }
}

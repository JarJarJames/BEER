using CloudSync.Cli;
using CloudSync.Steam;
using SteamKit2;
using SteamKit2.Internal;

namespace CloudSync.Commands;

/// `ownedgames`, and the per-app play-time read presence uses after a game stops.
static class OwnedGamesCommand
{
    public static async Task RunAsync(SteamSession s, ulong steamid)
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
        JsonOutput.Emit(new Dictionary<string, object?> { ["games"] = games });
    }

    /// Total minutes Steam has recorded for one app.
    public static async Task<long?> PlaytimeMinutesAsync(SteamSession s, ulong steamid, uint appid)
    {
        var player = s.Unified.CreateService<Player>();
        var req = new CPlayer_GetOwnedGames_Request
        {
            steamid = steamid,
            include_appinfo = false,
            include_played_free_games = true,
            include_free_sub = false,
        };
        req.appids_filter.Add(appid);

        var resp = await player.GetOwnedGames(req);
        if (resp.Result != EResult.OK)
            throw new Exception($"GetOwnedGames failed: {resp.Result}");
        return resp.Body.games.FirstOrDefault(g => g.appid == appid)?.playtime_forever;
    }
}

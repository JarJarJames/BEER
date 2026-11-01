using SteamKit2;

namespace CloudSync.Steam;

static class AppInfo
{
    /// PICS product info for a set of apps, keyed by appid. Access tokens are
    /// fetched first because most non-public app info is gated behind one.
    public static async Task<Dictionary<uint, SteamApps.PICSProductInfoCallback.PICSProductInfo>> RequestAsync(
        SteamApps apps, IEnumerable<uint> appIds)
    {
        var ids = appIds.Distinct().ToList();
        var found = new Dictionary<uint, SteamApps.PICSProductInfoCallback.PICSProductInfo>();
        if (ids.Count == 0) return found;

        var tokens = await apps.PICSGetAccessTokens(ids, new List<uint>());
        var requests = ids.Select(id =>
        {
            var req = new SteamKit2.SteamApps.PICSRequest(id);
            if (tokens.AppTokens.TryGetValue(id, out var token)) req.AccessToken = token;
            return req;
        }).ToList();

        foreach (var chunk in requests.Chunk(200))
        {
            var info = await apps.PICSGetProductInfo(chunk.ToList(), new List<SteamKit2.SteamApps.PICSRequest>());
            foreach (var result in info.Results ?? Enumerable.Empty<SteamApps.PICSProductInfoCallback>())
                foreach (var app in result.Apps.Values)
                    found[app.ID] = app;
        }
        return found;
    }
}

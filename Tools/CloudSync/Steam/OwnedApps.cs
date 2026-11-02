using SteamKit2;

namespace CloudSync.Steam;

static class OwnedApps
{
    /// Every appid granted by the packages this account holds a licence for.
    public static async Task<HashSet<uint>> RequestAsync(SteamSession s, SteamApps apps)
    {
        var licenses = await s.LicensesAsync();
        var requests = licenses
            .GroupBy(l => l.PackageID)
            .Select(g =>
            {
                var req = new SteamKit2.SteamApps.PICSRequest(g.Key);
                var token = g.Select(l => l.AccessToken).FirstOrDefault(t => t != 0);
                if (token != 0) req.AccessToken = token;
                return req;
            })
            .ToList();

        var owned = new HashSet<uint>();
        if (requests.Count == 0) return owned;

        // PICS rejects very large batches; chunk to stay well inside its limit.
        foreach (var chunk in requests.Chunk(500))
        {
            var info = await apps.PICSGetProductInfo(new List<SteamKit2.SteamApps.PICSRequest>(), chunk.ToList());
            foreach (var result in info.Results ?? Enumerable.Empty<SteamApps.PICSProductInfoCallback>())
                foreach (var package in result.Packages.Values)
                    foreach (var child in package.KeyValues["appids"].Children)
                        owned.Add(child.AsUnsignedInteger());
        }
        return owned;
    }
}

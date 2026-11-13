using SteamKit2;

namespace CloudSync.Steam;

static class OwnedApps
{
    /// Every appid granted by the packages this account holds a licence for.
    public static async Task<HashSet<uint>> RequestAsync(SteamSession s, SteamApps apps) =>
        (await RequestLicensedAsync(s, apps)).Apps;

    /// What this account's licences grant: `Apps`, and the `Depots`
    /// DepotDownloader may fetch. It downloads a depot only when a licensed
    /// package lists it under `depotids` or `appids` (a DLC's depot can share
    /// the DLC's id), so a game's depots for other regions or editions are left out.
    public static async Task<Licensed> RequestLicensedAsync(SteamSession s, SteamApps apps)
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

        var licensed = new Licensed(new HashSet<uint>(), new HashSet<uint>());
        if (requests.Count == 0) return licensed;

        // PICS rejects very large batches; chunk to stay well inside its limit.
        foreach (var chunk in requests.Chunk(500))
        {
            var info = await apps.PICSGetProductInfo(new List<SteamKit2.SteamApps.PICSRequest>(), chunk.ToList());
            foreach (var result in info.Results ?? Enumerable.Empty<SteamApps.PICSProductInfoCallback>())
                foreach (var package in result.Packages.Values)
                {
                    foreach (var child in package.KeyValues["appids"].Children)
                    {
                        licensed.Apps.Add(child.AsUnsignedInteger());
                        licensed.Depots.Add(child.AsUnsignedInteger());
                    }
                    foreach (var child in package.KeyValues["depotids"].Children)
                        licensed.Depots.Add(child.AsUnsignedInteger());
                }
        }
        return licensed;
    }
}

sealed record Licensed(HashSet<uint> Apps, HashSet<uint> Depots);

using CloudSync.Cli;
using CloudSync.Steam;
using SteamKit2;

namespace CloudSync.Commands;

static class DlcCommand
{
    // Report every DLC Steam lists for `appid`, flagged with whether this
    // account actually owns it.
    //
    // There is no "GetOwnedDLC" API — IPlayerService.GetOwnedGames returns
    // games only, never DLC. Ownership is derived the same way the real Steam
    // client (and DepotDownloader's AccountHasAccess) derives it: take the
    // packages this account is licensed for, ask PICS which appids each package
    // grants, and intersect that set with the app's DLC list.
    public static async Task RunAsync(SteamSession s, uint appid)
    {
        if (appid == 0) throw new Exception("dlc requires --appid");
        var apps = s.Client.GetHandler<SteamApps>()!;

        // Independent of everything below, and gated on a push Steam sends just
        // after logon — kick it off first and collect it once the DLC ids are known.
        var ownedTask = OwnedAppIdsAsync(s, apps);

        var baseInfo = await RequestAppInfoAsync(apps, new[] { appid });
        if (!baseInfo.TryGetValue(appid, out var baseApp) || baseApp is null)
            throw new Exception($"Steam returned no app info for {appid}");

        var dlcIds = new List<uint>();
        var seen = new HashSet<uint>();
        void AddDlc(uint id)
        {
            if (id != 0 && id != appid && seen.Add(id)) dlcIds.Add(id);
        }

        // The canonical list: appinfo → extended → listofdlc, comma separated.
        var listOfDlc = baseApp.KeyValues["extended"]["listofdlc"].AsString();
        if (!string.IsNullOrWhiteSpace(listOfDlc))
        {
            foreach (var part in listOfDlc.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                if (uint.TryParse(part, out var id)) AddDlc(id);
        }

        // Older titles omit listofdlc and instead tag the DLC's depot inside the
        // base app's depot section with a `dlcappid` key. Pick those up too.
        foreach (var depot in baseApp.KeyValues["depots"].Children)
        {
            var tag = depot["dlcappid"];
            if (tag != KeyValue.Invalid && uint.TryParse(tag.Value, out var id)) AddDlc(id);
        }

        var dlcInfo = await RequestAppInfoAsync(apps, dlcIds);
        var owned = await ownedTask;

        var result = new List<object>();
        foreach (var id in dlcIds)
        {
            dlcInfo.TryGetValue(id, out var info);
            var common = info?.KeyValues["common"];
            var name = common?["name"].AsString();
            result.Add(new Dictionary<string, object?>
            {
                ["appid"] = id,
                ["name"] = string.IsNullOrWhiteSpace(name) ? $"DLC {id}" : name,
                ["owned"] = owned.Contains(id),
                // Whether there is anything to download. Licence-only DLC
                // (season passes, artbooks) carry no installable depot, so the
                // UI can mark them "nothing to install" instead of failing.
                ["has_depots"] = info is not null && HasInstallableDepots(info),
            });
        }
        JsonOutput.Emit(new Dictionary<string, object?> { ["dlc"] = result });
    }

    /// Every appid granted by the packages this account holds a licence for.
    static async Task<HashSet<uint>> OwnedAppIdsAsync(SteamSession s, SteamApps apps)
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

    /// PICS product info for a set of apps, keyed by appid. Access tokens are
    /// fetched first because most non-public app info is gated behind one.
    static async Task<Dictionary<uint, SteamApps.PICSProductInfoCallback.PICSProductInfo>> RequestAppInfoAsync(
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

    /// True when the app owns at least one depot with a manifest that a Windows
    /// install would actually pull down.
    static bool HasInstallableDepots(SteamApps.PICSProductInfoCallback.PICSProductInfo info)
    {
        foreach (var depot in info.KeyValues["depots"].Children)
        {
            if (!uint.TryParse(depot.Name, out _)) continue;      // "branches", "baselanguages", …
            if (depot["manifests"] == KeyValue.Invalid) continue; // nothing to download

            var oslist = depot["config"]["oslist"];
            if (oslist != KeyValue.Invalid && !string.IsNullOrWhiteSpace(oslist.Value)
                && !oslist.Value.Split(',').Contains("windows"))
                continue;

            return true;
        }
        return false;
    }
}

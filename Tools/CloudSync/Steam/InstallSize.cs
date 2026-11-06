using SteamKit2;

namespace CloudSync.Steam;

static class InstallSize
{
    /// The bytes a Windows install of this app takes on disk, summed over the
    /// depots DepotDownloader would fetch for `-os windows -osarch 64` with its
    /// default English language. Null when Steam lists no size for any of them.
    public static ulong? Estimate(KeyValue appInfo, IReadOnlySet<uint> ownedAppIds) =>
        Total(Depots(appInfo, ownedAppIds));

    /// The depots DepotDownloader would fetch for `-app` alone. Depots tagged
    /// with `dlcappid` count only when `ownedAppIds` has that DLC:
    /// DepotDownloader pulls them for owned DLC only, and an unowned HD pack
    /// shouldn't block the base game.
    ///
    /// Each depot's size is its `maxsize` (the installed size), falling back
    /// to the public manifest's `size`.
    public static List<FetchedDepot> Depots(KeyValue appInfo, IReadOnlySet<uint> ownedAppIds)
    {
        var fetched = new List<FetchedDepot>();
        foreach (var depot in appInfo["depots"].Children)
        {
            // "branches", "baselanguages", …, and empty sections DepotDownloader skips.
            if (!uint.TryParse(depot.Name, out var id) || depot.Children.Count == 0) continue;
            uint? dlcAppId = null;
            var dlc = depot["dlcappid"];
            if (dlc != KeyValue.Invalid)
            {
                if (!uint.TryParse(dlc.Value, out var dlcId) || !ownedAppIds.Contains(dlcId)) continue;
                dlcAppId = dlcId;
            }
            if (!IsFetched(depot["config"])) continue;
            fetched.Add(new FetchedDepot(id, dlcAppId, SizeOf(depot)));
        }
        return fetched;
    }

    /// Null when none of `depots` lists a size.
    public static ulong? Total(IEnumerable<FetchedDepot> depots)
    {
        ulong total = 0;
        var found = false;
        foreach (var size in depots.Select(d => d.Size).OfType<ulong>())
        {
            total += size;
            found = true;
        }
        return found ? total : null;
    }

    /// Mirrors DepotDownloader's depot filter for the arguments BEER passes it.
    static bool IsFetched(KeyValue config)
    {
        if (config == KeyValue.Invalid) return true;
        if (Set(config["oslist"]) is { } os && !os.Split(',').Contains("windows")) return false;
        if (Set(config["osarch"]) is { } arch && arch != "64") return false;
        if (Set(config["language"]) is { } lang && lang != "english") return false;
        if (config["lowviolence"].AsString() == "1") return false;
        return true;
    }

    static ulong? SizeOf(KeyValue depot)
    {
        foreach (var value in new[] { depot["maxsize"], depot["manifests"]["public"]["size"] })
            if (value != KeyValue.Invalid && ulong.TryParse(value.Value, out var bytes) && bytes > 0)
                return bytes;
        return null;
    }

    static string? Set(KeyValue value) =>
        value == KeyValue.Invalid || string.IsNullOrWhiteSpace(value.Value) ? null : value.Value;
}

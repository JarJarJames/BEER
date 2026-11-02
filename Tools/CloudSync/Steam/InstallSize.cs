using SteamKit2;

namespace CloudSync.Steam;

static class InstallSize
{
    /// The bytes a Windows install of this app takes on disk, summed over the
    /// depots DepotDownloader would fetch for `-os windows -osarch 64` with its
    /// default English language. Null when Steam lists no size for any of them.
    ///
    /// Uses each depot's `maxsize` (the installed size), falling back to the
    /// public manifest's `size`. Depots tagged with `dlcappid` count only when
    /// `ownedAppIds` has that DLC: DepotDownloader pulls them for owned DLC
    /// only, and an unowned HD pack shouldn't block the base game.
    public static ulong? Estimate(KeyValue appInfo, IReadOnlySet<uint> ownedAppIds)
    {
        ulong total = 0;
        var found = false;
        foreach (var depot in appInfo["depots"].Children)
        {
            if (!uint.TryParse(depot.Name, out _)) continue;   // "branches", "baselanguages", …
            var dlc = depot["dlcappid"];
            if (dlc != KeyValue.Invalid && !(uint.TryParse(dlc.Value, out var dlcId) && ownedAppIds.Contains(dlcId)))
                continue;
            if (!IsFetched(depot["config"])) continue;

            var size = SizeOf(depot);
            if (size is null) continue;
            total += size.Value;
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

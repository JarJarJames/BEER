using SteamKit2;

namespace CloudSync.Steam;

/// Whether an installed game matches what Steam serves on its public branch.
/// `Untracked` when the folder has no DepotDownloader record to compare (an
/// install from an older BEER); `Unknown` when Steam's info gives nothing to
/// compare with.
enum GameUpdateStatus { Current, Update, Untracked, Unknown }

static class GameUpdate
{
    /// `sharedinstall` 1 marks one of Steam's shared redistributables (DirectX,
    /// VC++ installers), not the game's files. Shared game content is 2.
    const string RedistributableInstall = "1";

    /// Compare the depots in a game folder (`installed`, see `InstalledDepots`)
    /// with Steam's public manifests for the game. Only depots BEER's Update
    /// would download count, so the badge never asks for an update that
    /// downloading can't clear:
    ///
    /// - A depot left unfinished, or one Steam now serves a different manifest
    ///   for, is an update.
    /// - So is a game depot Steam added since (a DLC depot isn't: the player may
    ///   have left that DLC out).
    /// - Left out: depots the account's licences don't cover (other regions or
    ///   editions), DLC the player left out (`leftOut`) or no longer owns,
    ///   other platforms and languages, Steam's shared redistributables, and
    ///   depots that aren't the game's (a DLC fetched as its own app).
    ///
    /// A depot whose files come from another app (`depotfromapp`) is judged by
    /// that app's manifest, from `otherApps` (see `OtherApps`).
    public static GameUpdateStatus Compare(
        KeyValue appInfo, Licensed licensed, IReadOnlyDictionary<uint, ulong>? installed,
        IReadOnlySet<uint> leftOut, IReadOnlyDictionary<uint, KeyValue> otherApps)
    {
        if (installed is null || installed.Count == 0) return GameUpdateStatus.Untracked;

        var fetched = Fetched(appInfo, licensed, leftOut);
        var compared = false;
        foreach (var (depot, manifest) in installed)
        {
            if (!fetched.ContainsKey(depot)) continue;
            if (manifest == InstalledDepots.Unfinished) return GameUpdateStatus.Update;
            if (PublicManifest(appInfo, depot, otherApps) is not { } current) continue;
            if (current != manifest) return GameUpdateStatus.Update;
            compared = true;
        }

        foreach (var depot in fetched.Values)
        {
            if (depot.DlcAppId is null && !installed.ContainsKey(depot.Id)
                && PublicManifest(appInfo, depot.Id, otherApps) is not null)
                return GameUpdateStatus.Update;
        }
        // Nothing in the folder could be matched to Steam's info (app info
        // without depots, say): no answer, so the game keeps its last one.
        return compared ? GameUpdateStatus.Current : GameUpdateStatus.Unknown;
    }

    /// The depots DepotDownloader would download for this game now, by id.
    static Dictionary<uint, FetchedDepot> Fetched(KeyValue appInfo, Licensed licensed, IReadOnlySet<uint> leftOut)
    {
        // DepotDownloader skips its licence check for a free-to-download app.
        var free = appInfo["common"]["FreeToDownload"].AsBoolean();
        return InstallSize.Depots(appInfo, licensed.Apps)
            .Where(d => (free || licensed.Depots.Contains(d.Id)) && !leftOut.Contains(d.Id)
                && appInfo["depots"][d.Id.ToString()]["sharedinstall"].AsString() != RedistributableInstall)
            .ToDictionary(d => d.Id);
    }

    /// The apps whose info `Compare` needs besides the game's: the ones its
    /// depots take their manifests from.
    public static IEnumerable<uint> OtherApps(KeyValue appInfo) =>
        appInfo["depots"].Children
            .Where(d => d["manifests"] == KeyValue.Invalid && d["depotfromapp"] != KeyValue.Invalid)
            .Select(d => d["depotfromapp"].AsUnsignedInteger())
            .Where(id => id != 0)
            .Distinct();

    /// The manifest Steam serves for `depot` on the public branch, or null when
    /// none is listed. A depot with no manifests of its own takes them from its
    /// `depotfromapp`, as DepotDownloader does.
    static ulong? PublicManifest(KeyValue appInfo, uint depot, IReadOnlyDictionary<uint, KeyValue> otherApps)
    {
        var node = appInfo["depots"][depot.ToString()];
        if (node["manifests"] == KeyValue.Invalid && node["depotfromapp"] != KeyValue.Invalid)
        {
            return otherApps.TryGetValue(node["depotfromapp"].AsUnsignedInteger(), out var other)
                ? PublicManifest(other, depot)
                : null;
        }
        return PublicManifest(appInfo, depot);
    }

    /// Newer app info nests the id as `public/gid`; older app info has it as
    /// `public` itself.
    static ulong? PublicManifest(KeyValue appInfo, uint depot)
    {
        var node = appInfo["depots"][depot.ToString()]["manifests"]["public"];
        if (node == KeyValue.Invalid) return null;
        var gid = node["gid"] != KeyValue.Invalid ? node["gid"].Value : node.Value;
        return ulong.TryParse(gid, out var id) ? id : null;
    }

    public static string Name(GameUpdateStatus status) => status switch
    {
        GameUpdateStatus.Current => "current",
        GameUpdateStatus.Update => "update",
        GameUpdateStatus.Untracked => "untracked",
        _ => "unknown",
    };
}

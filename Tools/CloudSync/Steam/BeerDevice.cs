using System.Text;
using SteamKit2;

namespace CloudSync.Steam;

// The device BEER tells Steam it is.
//
// Every logon carries a machine ID. SteamKit2 builds it on macOS from the
// Mac's serial number and boot disk, the same inputs Steam's own client uses,
// so BEER logged on looking like the Mac's own Steam client — and the two
// signed each other out of Friends. BEER is its own device instead: a random
// ID made once per install and kept, so Steam sees the same BEER every launch.
sealed class BeerDevice : IMachineInfoProvider
{
    // SteamKit caches the generated machine ID per provider instance, so there
    // is exactly one.
    public static BeerDevice Current { get; private set; } = new(Guid.NewGuid().ToString("N"));

    readonly string _id;

    BeerDevice(string id) => _id = id;

    public string Id => _id;

    /// Use (creating if needed) the ID kept in `path`. Must run before the
    /// first SteamClient is made.
    public static void UseFile(string path) => Current = new(LoadOrCreate(path));

    internal static string LoadOrCreate(string path)
    {
        if (File.Exists(path))
        {
            var kept = File.ReadAllText(path).Trim();
            if (kept.Length > 0) return kept;
        }
        var id = Guid.NewGuid().ToString("N");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, id);
        return id;
    }

    // SteamKit hashes each of these; they only need to be stable and BEER's own.
    public byte[] GetMachineGuid() => Encoding.UTF8.GetBytes($"BEER-machine-{_id}");
    public byte[] GetMacAddress() => Encoding.UTF8.GetBytes($"BEER-mac-{_id}");
    public byte[] GetDiskId() => Encoding.UTF8.GetBytes($"BEER-disk-{_id}");
}

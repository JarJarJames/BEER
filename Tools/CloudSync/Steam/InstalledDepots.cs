using System.IO.Compression;
using ProtoBuf;

namespace CloudSync.Steam;

/// What DepotDownloader says is in a game folder: the manifest of each depot
/// it finished, from `<dir>/.DepotDownloader/depot.config`.
///
/// DepotDownloader writes a depot's manifest only once that depot is done, and
/// marks a depot it started but didn't finish with `Unfinished`, so the next
/// run checks every file.
static class InstalledDepots
{
    /// DepotDownloader's `INVALID_MANIFEST_ID`.
    public const ulong Unfinished = ulong.MaxValue;

    public static string ConfigPath(string installDir) =>
        Path.Combine(installDir, ".DepotDownloader", "depot.config");

    /// Null when the folder has no record, or one that can't be read.
    public static IReadOnlyDictionary<uint, ulong>? Read(string installDir)
    {
        var path = ConfigPath(installDir);
        if (!File.Exists(path)) return null;
        try
        {
            using var file = File.OpenRead(path);
            using var deflate = new DeflateStream(file, CompressionMode.Decompress);
            return Serializer.Deserialize<DepotConfig>(deflate).InstalledManifestIDs;
        }
        catch (Exception ex) when (ex is IOException or ProtoException or InvalidDataException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine($"Couldn't read {path}: {ex.Message}");
            return null;
        }
    }

    /// Write a record the way DepotDownloader does. Only tests need it.
    public static void Write(string installDir, IReadOnlyDictionary<uint, ulong> manifests)
    {
        var path = ConfigPath(installDir);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var config = new DepotConfig();
        foreach (var (depot, manifest) in manifests) config.InstalledManifestIDs[depot] = manifest;
        using var file = File.Create(path);
        using var deflate = new DeflateStream(file, CompressionMode.Compress);
        Serializer.Serialize(deflate, config);
    }

    /// DepotDownloader's `DepotConfigStore` layout (protobuf, deflate-compressed).
    /// The field number must match its own.
    [ProtoContract]
    sealed class DepotConfig
    {
        [ProtoMember(1)]
        public Dictionary<uint, ulong> InstalledManifestIDs { get; } = new();
    }
}

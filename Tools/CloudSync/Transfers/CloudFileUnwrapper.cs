using System.IO.Compression;
using System.Security.Cryptography;

namespace CloudSync.Transfers;

static class CloudFileUnwrapper
{
    // Steam stores a cloud save wrapped: the transfer is a zip holding exactly
    // one entry, which the Steam client names "z". Writing that payload verbatim
    // hands the game a zip where it expects its own save format — Mewgenics,
    // whose saves are SQLite, refuses it with "file is not a database".
    //
    // The wrapper is identified by its shape, not by the size fields: Steam does
    // not reliably report raw_file_size on this response (it came back as 0 or as
    // the compressed size for real Mewgenics saves), so trusting those silently
    // passed the zip straight through. A save that is genuinely a zip is left
    // alone — it takes more than one entry, or an entry not named "z".
    //
    // Anything that doesn't add up throws rather than returning bytes: a save we
    // cannot verify must never reach the disk.
    public static byte[] Unwrap(byte[] payload, uint fileSize, uint rawFileSize, byte[]? sha, string filename)
    {
        if (payload.Length < 4 || payload[0] != 'P' || payload[1] != 'K' || payload[2] != 3 || payload[3] != 4)
            return payload;

        using var archive = new ZipArchive(new MemoryStream(payload), ZipArchiveMode.Read);
        if (archive.Entries.Count != 1 || archive.Entries[0].FullName != "z") return payload;

        using var raw = new MemoryStream();
        using (var entryStream = archive.Entries[0].Open())
            entryStream.CopyTo(raw);
        var data = raw.ToArray();

        // Cross-check against raw_file_size only when Steam actually reported a
        // distinct one, and verify integrity against whichever form the SHA1
        // covers — it describes the stored blob for some files, the raw file for
        // others, and either one proves the transfer arrived intact.
        if (rawFileSize != 0 && rawFileSize != fileSize && data.Length != rawFileSize)
            throw new Exception($"{filename}: decompressed to {data.Length} bytes, expected {rawFileSize}.");
        if (sha != null && sha.Length > 0
            && !SHA1.HashData(data).SequenceEqual(sha)
            && !SHA1.HashData(payload).SequenceEqual(sha))
            throw new Exception($"{filename}: contents match neither the cloud SHA1 of the file nor of the transfer.");

        Console.Error.WriteLine(
            $"{filename}: unwrapped Steam's zip, {payload.Length} -> {data.Length} bytes " +
            $"(file_size={fileSize}, raw_file_size={rawFileSize})");
        return data;
    }
}

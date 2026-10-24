using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using CloudSync.Transfers;

namespace CloudSync.Tests.Transfers;

// Steam wraps a stored cloud file in a zip with one entry named "z". The
// unwrapper must remove exactly that wrapper, leave real zip saves alone, and
// refuse anything it can't verify, because its output is written over a save.
public class CloudFileUnwrapperTests
{
    static readonly byte[] Save = Encoding.UTF8.GetBytes("SQLite format 3\0 pretend save contents");

    static byte[] Zip(params (string Name, byte[] Data)[] entries)
    {
        using var buffer = new MemoryStream();
        using (var archive = new ZipArchive(buffer, ZipArchiveMode.Create, leaveOpen: true))
        {
            foreach (var (name, data) in entries)
            {
                using var stream = archive.CreateEntry(name).Open();
                stream.Write(data);
            }
        }
        return buffer.ToArray();
    }

    [Fact]
    public void A_file_that_is_not_a_zip_passes_through()
    {
        var result = CloudFileUnwrapper.Unwrap(Save, (uint)Save.Length, 0, SHA1.HashData(Save), "save.db");

        Assert.Equal(Save, result);
    }

    [Fact]
    public void Steams_single_z_entry_wrapper_is_removed()
    {
        var wrapped = Zip(("z", Save));

        var result = CloudFileUnwrapper.Unwrap(wrapped, (uint)wrapped.Length, (uint)Save.Length, SHA1.HashData(Save), "save.db");

        Assert.Equal(Save, result);
    }

    [Fact]
    public void A_sha_of_the_transfer_also_verifies_the_unwrapped_file()
    {
        var wrapped = Zip(("z", Save));

        var result = CloudFileUnwrapper.Unwrap(wrapped, (uint)wrapped.Length, 0, SHA1.HashData(wrapped), "save.db");

        Assert.Equal(Save, result);
    }

    [Fact]
    public void A_save_that_is_really_a_zip_is_left_alone()
    {
        var realZip = Zip(("profile.json", Save));

        var result = CloudFileUnwrapper.Unwrap(realZip, (uint)realZip.Length, 0, null, "saves.zip");

        Assert.Equal(realZip, result);
    }

    [Fact]
    public void A_multi_entry_zip_is_left_alone()
    {
        var realZip = Zip(("z", Save), ("y", Save));

        var result = CloudFileUnwrapper.Unwrap(realZip, (uint)realZip.Length, 0, null, "saves.zip");

        Assert.Equal(realZip, result);
    }

    [Fact]
    public void A_sha_matching_neither_form_is_rejected()
    {
        var wrapped = Zip(("z", Save));
        var wrongSha = SHA1.HashData(Encoding.UTF8.GetBytes("something else"));

        var ex = Assert.Throws<Exception>(() =>
            CloudFileUnwrapper.Unwrap(wrapped, (uint)wrapped.Length, 0, wrongSha, "save.db"));

        Assert.Contains("save.db", ex.Message);
    }

    [Fact]
    public void A_size_mismatch_against_a_reported_raw_size_is_rejected()
    {
        var wrapped = Zip(("z", Save));

        Assert.Throws<Exception>(() =>
            CloudFileUnwrapper.Unwrap(wrapped, (uint)wrapped.Length, (uint)Save.Length + 1, null, "save.db"));
    }
}

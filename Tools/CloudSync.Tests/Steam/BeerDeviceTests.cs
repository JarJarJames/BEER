using System.Text;
using CloudSync.Steam;

namespace CloudSync.Tests.Steam;

// #65: SteamKit2 builds its macOS machine ID from the Mac's serial number and
// boot disk, so BEER logged on as the same device as the Mac's own Steam
// client. BEER is its own device, kept stable across launches.
public class BeerDeviceTests : IDisposable
{
    readonly string _dir = Path.Combine(Path.GetTempPath(), $"BeerDeviceTests-{Guid.NewGuid():N}");
    string IdFile => Path.Combine(_dir, "steam-device-id");

    public void Dispose()
    {
        if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true);
    }

    [Fact]
    public void MakesAnIdOnceAndKeepsIt()
    {
        var first = BeerDevice.LoadOrCreate(IdFile);
        Assert.False(string.IsNullOrWhiteSpace(first));
        Assert.Equal(first, BeerDevice.LoadOrCreate(IdFile));
    }

    [Fact]
    public void TheSessionKeepsOneLoginIDPerInstall()
    {
        BeerDevice.UseFile(IdFile);
        var first = SteamSession.SessionLoginID;
        BeerDevice.UseFile(IdFile);
        Assert.Equal(first, SteamSession.SessionLoginID);
        Assert.True(first >= 0x4000_0000u, "clear of DepotDownloader's ids");

        BeerDevice.UseFile(Path.Combine(_dir, "another-install"));
        Assert.NotEqual(first, SteamSession.SessionLoginID);
    }

    [Fact]
    public void EveryPartIsBeersOwn()
    {
        BeerDevice.UseFile(IdFile);
        var id = BeerDevice.LoadOrCreate(IdFile);
        var device = BeerDevice.Current;
        Assert.Equal(id, device.Id);
        foreach (var part in new[] { device.GetMachineGuid(), device.GetMacAddress(), device.GetDiskId() })
            Assert.Contains(id, Encoding.UTF8.GetString(part));
    }
}

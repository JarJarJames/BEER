using CloudSync.Steam;
using SteamKit2;

namespace CloudSync.Tests.Steam;

// Fixtures mirror the `depots` section of PICS app info. No Steam session or
// network involved.
public class InstallSizeTests
{
    sealed record Depot(string Id, string? MaxSize = null, string? ManifestSize = null,
        string? OsList = null, string? OsArch = null, string? Language = null,
        string? LowViolence = null, string? DlcAppId = null);

    static KeyValue App(params Depot[] depots)
    {
        var root = new KeyValue("appinfo");
        var section = new KeyValue("depots");
        root["depots"] = section;
        section["branches"] = new KeyValue("branches");
        foreach (var d in depots)
        {
            var node = new KeyValue(d.Id);
            section[d.Id] = node;
            if (d.MaxSize is not null) node["maxsize"] = new KeyValue("maxsize", d.MaxSize);
            if (d.DlcAppId is not null) node["dlcappid"] = new KeyValue("dlcappid", d.DlcAppId);
            if (d.ManifestSize is not null)
            {
                var manifests = new KeyValue("manifests");
                var pub = new KeyValue("public");
                node["manifests"] = manifests;
                manifests["public"] = pub;
                pub["size"] = new KeyValue("size", d.ManifestSize);
            }
            var cfg = new KeyValue("config");
            node["config"] = cfg;
            if (d.OsList is not null) cfg["oslist"] = new KeyValue("oslist", d.OsList);
            if (d.OsArch is not null) cfg["osarch"] = new KeyValue("osarch", d.OsArch);
            if (d.Language is not null) cfg["language"] = new KeyValue("language", d.Language);
            if (d.LowViolence is not null) cfg["lowviolence"] = new KeyValue("lowviolence", d.LowViolence);
        }
        return root;
    }

    [Fact]
    public void SumsWindowsDepots()
    {
        var app = App(
            new Depot("101", MaxSize: "1000", OsList: "windows"),
            new Depot("102", MaxSize: "250"));
        Assert.Equal(1250UL, InstallSize.Estimate(app));
    }

    [Fact]
    public void SkipsDepotsDepotDownloaderWouldNotFetch()
    {
        var app = App(
            new Depot("101", MaxSize: "1000", OsList: "windows,linux"),
            new Depot("102", MaxSize: "9000", OsList: "macos"),
            new Depot("103", MaxSize: "9000", OsArch: "32"),
            new Depot("104", MaxSize: "9000", Language: "german"),
            new Depot("105", MaxSize: "9000", LowViolence: "1"),
            new Depot("106", MaxSize: "9000", DlcAppId: "555"),
            new Depot("107", MaxSize: "10", OsArch: "64", Language: "english"));
        Assert.Equal(1010UL, InstallSize.Estimate(app));
    }

    [Fact]
    public void FallsBackToTheManifestSize()
    {
        var app = App(
            new Depot("101", ManifestSize: "700"),
            new Depot("102", MaxSize: "300", ManifestSize: "1"));
        Assert.Equal(1000UL, InstallSize.Estimate(app));
    }

    [Fact]
    public void UnknownWhenNoDepotListsASize()
    {
        Assert.Null(InstallSize.Estimate(App(new Depot("101"), new Depot("102", MaxSize: "0"))));
        Assert.Null(InstallSize.Estimate(new KeyValue("appinfo")));
    }
}

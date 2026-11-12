using CloudSync.Commands;
using CloudSync.Steam;
using SteamKit2;

namespace CloudSync.Tests.Steam;

// Fixtures mirror the `depots` section of PICS app info and the record
// DepotDownloader leaves in a game folder. No Steam session or network involved.
public class GameUpdateTests : IDisposable
{
    readonly string _dir = Path.Combine(Path.GetTempPath(), "GameUpdateTests-" + Guid.NewGuid());

    public void Dispose()
    {
        if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true);
    }

    sealed record Depot(
        string Id, string? Gid, string? DlcAppId = null, bool OldLayout = false,
        string? Language = null, string OsList = "windows", string? LowViolence = null,
        string? FromApp = null, string? SharedInstall = null);

    static KeyValue App(params Depot[] depots) => App(free: false, depots);

    static KeyValue App(bool free, params Depot[] depots)
    {
        var root = new KeyValue("appinfo");
        if (free)
        {
            root["common"] = new KeyValue("common");
            root["common"]["FreeToDownload"] = new KeyValue("FreeToDownload", "1");
        }
        var section = new KeyValue("depots");
        root["depots"] = section;
        section["branches"] = new KeyValue("branches");
        foreach (var d in depots)
        {
            var node = new KeyValue(d.Id);
            section[d.Id] = node;
            if (d.DlcAppId is not null) node["dlcappid"] = new KeyValue("dlcappid", d.DlcAppId);
            if (d.FromApp is not null) node["depotfromapp"] = new KeyValue("depotfromapp", d.FromApp);
            if (d.SharedInstall is not null) node["sharedinstall"] = new KeyValue("sharedinstall", d.SharedInstall);
            var cfg = new KeyValue("config");
            node["config"] = cfg;
            cfg["oslist"] = new KeyValue("oslist", d.OsList);
            if (d.Language is not null) cfg["language"] = new KeyValue("language", d.Language);
            if (d.LowViolence is not null) cfg["lowviolence"] = new KeyValue("lowviolence", d.LowViolence);
            if (d.Gid is null) continue;
            var manifests = new KeyValue("manifests");
            node["manifests"] = manifests;
            if (d.OldLayout)
            {
                manifests["public"] = new KeyValue("public", d.Gid);
            }
            else
            {
                var pub = new KeyValue("public");
                manifests["public"] = pub;
                pub["gid"] = new KeyValue("gid", d.Gid);
            }
        }
        return root;
    }

    static Dictionary<uint, ulong> Installed(params (uint depot, ulong manifest)[] depots) =>
        depots.ToDictionary(d => d.depot, d => d.manifest);

    /// Licences granting the app ids and depot ids in `ids`.
    static Licensed Owning(params uint[] ids) => new(ids.ToHashSet(), ids.ToHashSet());

    static readonly Licensed GameOwned = Owning(100, 101, 102, 103, 104, 105, 106);

    static GameUpdateStatus Check(
        KeyValue app, Dictionary<uint, ulong>? installed, Licensed? licensed = null,
        uint[]? leftOut = null, Dictionary<uint, KeyValue>? otherApps = null) =>
        GameUpdate.Compare(app, licensed ?? GameOwned, installed,
            (leftOut ?? []).ToHashSet(), otherApps ?? new Dictionary<uint, KeyValue>());

    // MARK: What changed on Steam

    [Fact]
    public void MatchingManifestsAreCurrent()
    {
        var app = App(new Depot("101", "111"), new Depot("102", "222"));
        Assert.Equal(GameUpdateStatus.Current, Check(app, Installed((101, 111), (102, 222))));
    }

    [Fact]
    public void ANewerManifestIsAnUpdate()
    {
        var app = App(new Depot("101", "112"), new Depot("102", "222"));
        Assert.Equal(GameUpdateStatus.Update, Check(app, Installed((101, 111), (102, 222))));
    }

    [Fact]
    public void ReadsTheOlderManifestLayout()
    {
        var app = App(new Depot("101", "111", OldLayout: true));
        Assert.Equal(GameUpdateStatus.Current, Check(app, Installed((101, 111))));
        Assert.Equal(GameUpdateStatus.Update, Check(app, Installed((101, 110))));
    }

    [Fact]
    public void AnUnfinishedDepotIsAnUpdate()
    {
        var app = App(new Depot("101", "111"));
        Assert.Equal(GameUpdateStatus.Update, Check(app, Installed((101, InstalledDepots.Unfinished))));
    }

    [Fact]
    public void AGameDepotSteamAddedIsAnUpdate()
    {
        var app = App(new Depot("101", "111"), new Depot("103", "333"));
        Assert.Equal(GameUpdateStatus.Update, Check(app, Installed((101, 111))));
    }

    [Fact]
    public void AnUpdatedDlcIsAnUpdate()
    {
        var app = App(new Depot("101", "111"), new Depot("150", "556", DlcAppId: "900"));
        Assert.Equal(GameUpdateStatus.Update,
            Check(app, Installed((101, 111), (150, 555)), Owning(101, 900, 150)));
    }

    // MARK: What Update wouldn't download

    [Fact]
    public void AGameDepotTheLicencesDontCoverIsNotAnUpdate()
    {
        // Kingdom Come: Deliverance lists Windows depots for other regions or
        // editions that a player's licence doesn't include, so DepotDownloader
        // never fetched them.
        var app = App(new Depot("379432", "111"), new Depot("379434", "444"), new Depot("379437", "777"));
        Assert.Equal(GameUpdateStatus.Current,
            Check(app, Installed((379432, 111)), Owning(379430, 379432)));
    }

    [Fact]
    public void AFreeGameNeedsNoLicence()
    {
        // DepotDownloader skips its licence check for a free-to-download app.
        var app = App(free: true, new Depot("101", "111"), new Depot("103", "333"));
        Assert.Equal(GameUpdateStatus.Update, Check(app, Installed((101, 111)), Owning()));
    }

    [Fact]
    public void ADlcThePlayerHasntDownloadedIsNotAnUpdate()
    {
        var app = App(new Depot("101", "111"), new Depot("150", "555", DlcAppId: "900"));
        Assert.Equal(GameUpdateStatus.Current, Check(app, Installed((101, 111)), Owning(101, 900, 150)));
    }

    [Fact]
    public void ADlcLeftOutSinceItDownloadedIsIgnored()
    {
        // Unticked on a later download: Update won't fetch it, even unfinished.
        var app = App(new Depot("101", "111"), new Depot("150", "556", DlcAppId: "900"));
        var licensed = Owning(101, 900, 150);
        Assert.Equal(GameUpdateStatus.Current,
            Check(app, Installed((101, 111), (150, 555)), licensed, leftOut: [150]));
        Assert.Equal(GameUpdateStatus.Current,
            Check(app, Installed((101, 111), (150, InstalledDepots.Unfinished)), licensed, leftOut: [150]));
    }

    [Fact]
    public void ADlcNoLongerOwnedIsIgnored()
    {
        // Refunded, or a family member's game no longer shared.
        var app = App(new Depot("101", "111"), new Depot("150", "556", DlcAppId: "900"));
        Assert.Equal(GameUpdateStatus.Current, Check(app, Installed((101, 111), (150, 555)), Owning(101)));
    }

    [Fact]
    public void OtherPlatformsLanguagesAndCutsAreIgnored()
    {
        var app = App(
            new Depot("101", "111"),
            new Depot("104", "444", Language: "german"),
            new Depot("105", "555", OsList: "linux"),
            new Depot("106", "666", LowViolence: "1"));
        Assert.Equal(GameUpdateStatus.Current, Check(app, Installed((101, 111))));
    }

    [Fact]
    public void SteamsRedistributablesAreIgnored()
    {
        // 228986 is a VC++ installer from Steamworks Common Redistributables:
        // its updates aren't the game's, and one would badge every game at once.
        var app = App(new Depot("101", "111"),
            new Depot("228986", null, FromApp: "228980", SharedInstall: "1"),
            new Depot("228990", null, FromApp: "228980", SharedInstall: "1"));
        var redist = App(new Depot("228986", "9001"), new Depot("228990", "9002"));
        Assert.Equal(GameUpdateStatus.Current,
            Check(app, Installed((101, 111), (228986, 8000)), Owning(101, 228986, 228990),
                otherApps: new() { [228980] = redist }));
    }

    [Fact]
    public void SharedGameFilesAreJudgedByTheAppTheyComeFrom()
    {
        // Like Nuclear Dawn's server, whose depot 17712 holds the game's files.
        var app = App(new Depot("101", "111"), new Depot("102", null, FromApp: "200", SharedInstall: "2"));
        var licensed = Owning(101, 102);
        Assert.Equal(new uint[] { 200 }, GameUpdate.OtherApps(app));

        Assert.Equal(GameUpdateStatus.Current, Check(app, Installed((101, 111), (102, 222)), licensed,
            otherApps: new() { [200] = App(new Depot("102", "222")) }));
        Assert.Equal(GameUpdateStatus.Update, Check(app, Installed((101, 111), (102, 222)), licensed,
            otherApps: new() { [200] = App(new Depot("102", "223")) }));
        // Without that app's info the depot can't be judged; the rest still is.
        Assert.Equal(GameUpdateStatus.Current, Check(app, Installed((101, 111), (102, 222)), licensed));
    }

    [Fact]
    public void DepotsOutsideTheGameAreLeftOut()
    {
        // 228983 is a shared redistributable; 777 a DLC fetched as its own app.
        var app = App(new Depot("101", "111"), new Depot("228983", null));
        Assert.Equal(GameUpdateStatus.Current,
            Check(app, Installed((101, 111), (228983, 9), (777, 7))));
    }

    // MARK: No answer

    [Fact]
    public void NoRecordIsUntracked()
    {
        var app = App(new Depot("101", "111"));
        Assert.Equal(GameUpdateStatus.Untracked, Check(app, null));
        Assert.Equal(GameUpdateStatus.Untracked, Check(app, Installed()));
    }

    [Fact]
    public void NothingToCompareIsUnknown()
    {
        // App info without the depots (no access to them), or none of the
        // folder's depots still listed.
        Assert.Equal(GameUpdateStatus.Unknown, Check(new KeyValue("appinfo"), Installed((101, 111))));
        Assert.Equal(GameUpdateStatus.Unknown, Check(App(new Depot("102", "222", DlcAppId: "900")), Installed((101, 111))));
    }

    [Fact]
    public void NamesEveryStatus()
    {
        Assert.Equal(new[] { "current", "update", "untracked", "unknown" },
            Enum.GetValues<GameUpdateStatus>().Select(GameUpdate.Name));
    }

    [Fact]
    public void ReadsTheRecordDepotDownloaderWrites()
    {
        InstalledDepots.Write(_dir, Installed((101, 111), (102, InstalledDepots.Unfinished)));
        var read = InstalledDepots.Read(_dir);
        Assert.NotNull(read);
        Assert.Equal(111UL, read![101]);
        Assert.Equal(InstalledDepots.Unfinished, read[102]);
    }

    [Fact]
    public void AMissingOrBrokenRecordReadsAsNone()
    {
        Assert.Null(InstalledDepots.Read(_dir));
        Directory.CreateDirectory(Path.GetDirectoryName(InstalledDepots.ConfigPath(_dir))!);
        File.WriteAllText(InstalledDepots.ConfigPath(_dir), "not a depot config");
        Assert.Null(InstalledDepots.Read(_dir));
    }

    [Fact]
    public void ReadsJobs()
    {
        var jobs = UpdateCheckCommand.ReadJobs("""
            [{"appid": 10, "dir": "/games/a", "leftout": [150, 151]}, {"appid": 11, "dir": "/games/b"},
             {"appid": 0, "dir": "/x"}, {"appid": 20, "dir": ""}]
            """);
        Assert.Equal(new uint[] { 10, 11 }, jobs.Select(j => j.AppId));
        Assert.Equal("/games/a", jobs[0].Dir);
        Assert.Equal(new uint[] { 150, 151 }, jobs[0].LeftOut.Order());
        Assert.Empty(jobs[1].LeftOut);
    }
}

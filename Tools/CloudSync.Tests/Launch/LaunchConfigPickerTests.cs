using CloudSync.Launch;
using SteamKit2;

namespace CloudSync.Tests.Launch;

// Fixtures mirror real `config/launch` sections from PICS app info. No Steam
// session or network involved.
public class LaunchConfigPickerTests
{
    sealed record Entry(string Executable, string? OsList = null, string? Type = null,
        string? OsArch = null, string? BetaKey = null, string? OwnsDlc = null, string? Arguments = null);

    static KeyValue App(params Entry[] entries)
    {
        var root = new KeyValue("appinfo");
        var config = new KeyValue("config");
        var launch = new KeyValue("launch");
        root["config"] = config;
        config["launch"] = launch;
        for (var i = 0; i < entries.Length; i++)
        {
            var e = entries[i];
            var node = new KeyValue(i.ToString());
            launch[node.Name!] = node;
            node["executable"] = new KeyValue("executable", e.Executable);
            if (e.Type is not null) node["type"] = new KeyValue("type", e.Type);
            if (e.Arguments is not null) node["arguments"] = new KeyValue("arguments", e.Arguments);
            var cfg = new KeyValue("config");
            node["config"] = cfg;
            if (e.OsList is not null) cfg["oslist"] = new KeyValue("oslist", e.OsList);
            if (e.OsArch is not null) cfg["osarch"] = new KeyValue("osarch", e.OsArch);
            if (e.BetaKey is not null) cfg["betakey"] = new KeyValue("betakey", e.BetaKey);
            if (e.OwnsDlc is not null) cfg["ownsdlc"] = new KeyValue("ownsdlc", e.OwnsDlc);
        }
        return root;
    }

    static List<string> Executables(KeyValue app) =>
        LaunchConfigPicker.Pick(app).Select(e => e.Executable).ToList();

    [Fact]
    public void BindingOfIsaacPicksTheGameNotOtherPlatforms()
    {
        // appid 250900. The Mod Uploader isn't listed at all; the old
        // largest-.exe heuristic picked it anyway.
        var app = App(
            new Entry("isaac-ng.exe", OsList: "windows"),
            new Entry("run-x64.sh", OsList: "linux", OsArch: "64"),
            new Entry("The Binding of Isaac Rebirth.app", OsList: "macos"),
            new Entry("run-i386.sh", OsList: "linux", OsArch: "32"));

        Assert.Equal(new[] { "isaac-ng.exe" }, Executables(app));
    }

    [Fact]
    public void KeepsBackslashPathsAsSteamStoresThem()
    {
        var app = App(new Entry(@"Bin\Win64\KingdomCome.exe", OsList: "windows", OsArch: "64", Type: "none"));

        Assert.Equal(new[] { @"Bin\Win64\KingdomCome.exe" }, Executables(app));
    }

    [Fact]
    public void DropsBetaVrEditorAndServerEntries()
    {
        var app = App(
            new Entry("beta.exe", BetaKey: "experimental"),
            new Entry("vr.exe", Type: "vr"),
            new Entry("editor.exe", Type: "editor"),
            new Entry("server.exe", Type: "server"),
            new Entry("game.exe"));

        Assert.Equal(new[] { "game.exe" }, Executables(app));
    }

    [Fact]
    public void RanksDefaultThen64BitThenDlcLast()
    {
        var app = App(
            new Entry("dlc.exe", OwnsDlc: "12345"),
            new Entry("option.exe", Type: "option1", OsArch: "64"),
            new Entry("game32.exe", Type: "default", OsArch: "32"),
            new Entry("game64.exe", Type: "default", OsArch: "64"));

        Assert.Equal(new[] { "game64.exe", "game32.exe", "option.exe", "dlc.exe" }, Executables(app));
    }

    [Fact]
    public void AnEntryWithNoOsListCountsAsWindows()
    {
        var app = App(new Entry("Game.exe", Arguments: " -windowed "));

        var entry = Assert.Single(LaunchConfigPicker.Pick(app));
        Assert.Equal("-windowed", entry.Arguments);
    }

    [Fact]
    public void NoLaunchSectionYieldsNothing()
    {
        Assert.Empty(LaunchConfigPicker.Pick(new KeyValue("appinfo")));
    }
}

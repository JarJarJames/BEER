using CloudSync.Steam;
using SteamKit2;

namespace CloudSync.Tests.Steam;

// Fixtures mirror a real `ufs/savefiles` section from PICS app info. No Steam
// session or network involved.
public class UfsSaveFilesTests
{
    static KeyValue App(params KeyValue[] rules)
    {
        var root = new KeyValue("appinfo");
        var ufs = new KeyValue("ufs");
        var saveFiles = new KeyValue("savefiles");
        root["ufs"] = ufs;
        ufs["savefiles"] = saveFiles;
        for (var i = 0; i < rules.Length; i++) saveFiles[i.ToString()] = rules[i];
        return root;
    }

    static KeyValue Rule(string? root, string? path = null, string? pattern = null,
        string? recursive = null, params string[] platforms)
    {
        var node = new KeyValue("rule");
        if (root is not null) node["root"] = new KeyValue("root", root);
        if (path is not null) node["path"] = new KeyValue("path", path);
        if (pattern is not null) node["pattern"] = new KeyValue("pattern", pattern);
        if (recursive is not null) node["recursive"] = new KeyValue("recursive", recursive);
        if (platforms.Length > 0)
        {
            var list = new KeyValue("platforms");
            for (var i = 0; i < platforms.Length; i++) list[(i + 1).ToString()] = new KeyValue(null, platforms[i]);
            node["platforms"] = list;
        }
        return node;
    }

    [Fact]
    public void ReportsEachRuleAsSteamListsIt()
    {
        var rules = UfsSaveFiles.Parse(App(
            Rule("WinSavedGames", "kingdomcome/saves", "*", "1", "Windows")));

        var rule = Assert.Single(rules);
        Assert.Equal("WinSavedGames", rule["root"]);
        Assert.Equal("kingdomcome/saves", rule["path"]);
        Assert.Equal("*", rule["pattern"]);
        Assert.Equal(true, rule["recursive"]);
        Assert.Equal(new List<string?> { "Windows" }, rule["platforms"]);
    }

    [Fact]
    public void MissingFieldsGetSteamsDefaults()
    {
        var rule = Assert.Single(UfsSaveFiles.Parse(App(Rule("WinAppDataLocal"))));
        Assert.Equal("", rule["path"]);
        Assert.Equal("*", rule["pattern"]);
        Assert.Equal(false, rule["recursive"]);
        Assert.Empty((List<string?>)rule["platforms"]!);
    }

    [Fact]
    public void RulesWithoutARootAreDropped()
    {
        Assert.Empty(UfsSaveFiles.Parse(App(Rule(null, "saves"))));
    }

    [Fact]
    public void AnAppWithoutUfsHasNoRules()
    {
        Assert.Empty(UfsSaveFiles.Parse(new KeyValue("appinfo")));
    }
}

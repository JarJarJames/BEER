using SteamKit2;

namespace CloudSync.Launch;

// Steam's Play button runs an entry from the app's `config/launch` section, not
// whichever .exe happens to be biggest. This narrows that list to what a
// Windows install on the public branch could run, best first.
//
// Steam keeps entries for the current OS, drops ones tied to a beta branch or a
// DLC the user lacks, and runs the default. VR, editor and dedicated-server
// entries are only offered from the picker, so they are dropped here too.
static class LaunchConfigPicker
{
    static readonly HashSet<string> ExcludedTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "server", "editor", "vr", "openvrdashboard", "othervr", "osvr", "openxr",
    };

    /// `appInfo` is the app's root KeyValue (the one holding `config`).
    public static List<LaunchEntry> Pick(KeyValue appInfo)
    {
        var ranked = new List<(LaunchEntry Entry, int Rank, int Index)>();
        foreach (var child in appInfo["config"]["launch"].Children)
        {
            var executable = child["executable"].AsString()?.Trim();
            if (string.IsNullOrEmpty(executable)) continue;

            var config = child["config"];
            var oslist = config["oslist"].AsString();
            if (!string.IsNullOrWhiteSpace(oslist)
                && !oslist.Split(',', StringSplitOptions.TrimEntries).Contains("windows", StringComparer.OrdinalIgnoreCase))
                continue;
            if (!string.IsNullOrWhiteSpace(config["betakey"].AsString())) continue;

            var type = child["type"].AsString()?.Trim() ?? "";
            if (ExcludedTypes.Contains(type)) continue;

            ranked.Add((
                new LaunchEntry(
                    executable,
                    child["arguments"].AsString()?.Trim() ?? "",
                    child["workingdir"].AsString()?.Trim() ?? "",
                    type,
                    child["description"].AsString() ?? ""),
                Rank(type, config),
                int.TryParse(child.Name, out var index) ? index : int.MaxValue));
        }
        return ranked
            .OrderBy(r => r.Rank)
            .ThenBy(r => r.Index)
            .Select(r => r.Entry)
            .ToList();
    }

    // Lower is better. The game's own default comes first, then 64-bit over
    // unspecified over 32-bit, and entries that need a DLC last.
    static int Rank(string type, KeyValue config)
    {
        var isDefault = type is "" || type.Equals("default", StringComparison.OrdinalIgnoreCase)
            || type.Equals("none", StringComparison.OrdinalIgnoreCase);
        var arch = config["osarch"].AsString() switch
        {
            "64" => 0,
            "32" => 2,
            _ => 1,
        };
        var needsDlc = !string.IsNullOrWhiteSpace(config["ownsdlc"].AsString()) ? 1 : 0;
        return (needsDlc * 100) + (isDefault ? 0 : 10) + arch;
    }
}

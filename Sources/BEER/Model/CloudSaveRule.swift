import Foundation

/// One entry from a game's Steam Cloud `ufs/savefiles` config: the folder the
/// game saves into, and which files there belong in the cloud. Steam scans
/// these to find saves that have no cloud copy yet.
struct CloudSaveRule: Equatable {
    /// Steam root token without the %…%, e.g. "WinSavedGames" or "gameinstall".
    let root: String
    /// Folder under the root. May hold `{64BitSteamID}` / `{Steam3AccountID}`.
    let path: String
    /// Filename glob, e.g. "*" or "*.sav".
    let pattern: String
    let recursive: Bool
    /// Platforms the rule applies to. Empty means all of them.
    let platforms: [String]

    init(root: String, path: String, pattern: String = "*", recursive: Bool = false, platforms: [String] = []) {
        self.root = root
        self.path = path
        self.pattern = pattern
        self.recursive = recursive
        self.platforms = platforms
    }

    init?(json: [String: Any]) {
        guard let root = json["root"] as? String, !root.isEmpty else { return nil }
        let pattern = json["pattern"] as? String ?? ""
        self.init(
            root: root,
            path: json["path"] as? String ?? "",
            pattern: pattern.isEmpty ? "*" : pattern,
            recursive: json["recursive"] as? Bool ?? false,
            platforms: json["platforms"] as? [String] ?? []
        )
    }

    /// Games run here as their Windows build, so only Windows rules count.
    var appliesToWindows: Bool {
        platforms.isEmpty || platforms.contains { ["windows", "all"].contains($0.lowercased()) }
    }
}

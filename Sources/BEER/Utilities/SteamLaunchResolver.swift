import Foundation

/// Turns Steam's launch entries into a file in this install. Steam's list is
/// authoritative where `LaunchExecutableFinder` can only guess — The Binding
/// of Isaac ships a Mod Uploader bigger than the game itself.
enum SteamLaunchResolver {
    struct Target: Equatable {
        let executable: URL
        let arguments: String
    }

    /// The first entry whose executable is actually in the install.
    static func resolve(_ entries: [CloudSyncClient.LaunchEntry], in installDir: URL) -> Target? {
        for entry in entries {
            if let url = locate(entry.executable, in: installDir) {
                return Target(executable: url, arguments: entry.arguments)
            }
        }
        return nil
    }

    /// Steam writes `Bin\Win64\Game.exe` and is often cased differently from
    /// the depot's files, so each component is matched case-insensitively.
    /// Anything that would climb out of the install is rejected.
    static func locate(_ relativePath: String, in root: URL) -> URL? {
        let fm = FileManager.default
        let components = relativePath
            .split(whereSeparator: { $0 == "\\" || $0 == "/" })
            .map(String.init)
            .filter { $0 != "." }
        guard !components.isEmpty, !components.contains("..") else { return nil }

        var current = root
        for component in components {
            let exact = current.appendingPathComponent(component)
            if fm.fileExists(atPath: exact.path) {
                current = exact
                continue
            }
            guard let match = (try? fm.contentsOfDirectory(atPath: current.path))?
                .first(where: { $0.caseInsensitiveCompare(component) == .orderedSame }) else { return nil }
            current = current.appendingPathComponent(match)
        }
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: current.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
        return current
    }
}

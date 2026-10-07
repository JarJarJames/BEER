import Foundation

extension Bottle {
    /// Resolve the game's install directory. Bottles created after this change
    /// have it stored explicitly; older bottles (like the user's existing KCD)
    /// fall back to walking up from `gameLaunchExecutable` until we hit a
    /// directory whose parent is named "Games".
    var resolvedInstallDirectory: URL? {
        if let stored = gameInstallDirectory {
            let url = URL(fileURLWithPath: stored)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        guard let exe = gameLaunchExecutable else { return nil }
        var current = URL(fileURLWithPath: exe).deletingLastPathComponent()
        // Walk up at most 12 levels looking for a directory whose parent is "Games".
        for _ in 0..<12 {
            if current.deletingLastPathComponent().lastPathComponent == "Games" {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }   // hit /
            current = parent
        }
        return nil
    }
}

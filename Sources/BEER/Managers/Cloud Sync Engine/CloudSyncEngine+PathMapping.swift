import Foundation

extension CloudSyncEngine {
    /// A cheap signature of every tracked save file's size and modification
    /// time. Nil when we have not yet learned where this game's saves live.
    ///
    /// Comparing this across a play session answers "did the game write
    /// anything?" locally. That matters because the alternative — always
    /// pushing — spends a Steam logon per launch, and a game that crash-loops
    /// turns that into a burst of logons that Steam starts refusing outright,
    /// taking the library refresh and the presence session down with it.
    func localSaveFingerprint(appID: Int) -> String? {
        guard let dirs = knownSaveDirs[appID], !dirs.isEmpty else { return nil }
        let fm = FileManager.default
        var parts: [String] = []
        for dir in dirs.sorted(by: { $0.path < $1.path }) {
            guard let walker = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
                let size = values?.fileSize ?? 0
                parts.append("\(url.path):\(mtime):\(size)")
            }
        }
        return parts.isEmpty ? nil : parts.sorted().joined(separator: "|")
    }

    func resolveWineUserHome(for bottle: Bottle) throws -> URL {
        let usersDir = AppPaths.prefixURL(for: bottle)
            .appendingPathComponent("drive_c", isDirectory: true)
            .appendingPathComponent("users", isDirectory: true)
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: usersDir.path)) ?? []
        // Prefer "crossover" — our pinned Wine username (see BottleStore). A
        // bottle may also have a stale login-named folder from before we pinned
        // it; the game now always uses crossover, so sync must target it too.
        let candidate = entries.first(where: { $0 == "crossover" })
            ?? entries.filter { !$0.hasPrefix(".") }.first(where: { $0 != "Public" })
            ?? entries.first
        guard let user = candidate else { throw CloudSyncError.userHomeNotFound(usersDir) }
        return usersDir.appendingPathComponent(user, isDirectory: true)
    }

    /// Split a Steam cloud filename into (root token, remainder). The protocol
    /// uses "%Token%/rest"; some forms drop the %…%. Returns nil remainder-safe.
    func splitRoot(_ filename: String) -> (root: String, rest: String) {
        var name = filename.replacingOccurrences(of: "\\", with: "/")
        if name.hasPrefix("/") { name.removeFirst() }
        if name.hasPrefix("%"), let close = name.dropFirst().firstIndex(of: "%") {
            let token = String(name[name.index(after: name.startIndex)..<close])
            var rest = String(name[name.index(after: close)...])
            if rest.hasPrefix("/") { rest.removeFirst() }
            return (token, rest)
        }
        // No %…%: first path component is the root token.
        let parts = name.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        return (String(parts.first ?? ""), parts.count > 1 ? String(parts[1]) : "")
    }

    /// Map a Steam cloud filename to the local file URL inside the bottle.
    func mapToLocal(_ filename: String, userHome: URL, installDir: URL?) -> URL? {
        let (token, rest) = splitRoot(filename)
        let key = token.uppercased()

        let base: URL
        if key == "GAMEINSTALL" {
            guard let installDir else { return nil }
            base = installDir
        } else if let rel = steamRootRouting[key] {
            base = rel.isEmpty ? userHome : appendingComponents(rel, to: userHome, isDir: true)
        } else {
            // Unknown root — treat the token itself as a folder under the home.
            base = appendingComponents(token, to: userHome, isDir: true)
        }
        return rest.isEmpty ? base : appendingComponents(rest, to: base, isDir: false)
    }

    /// The remote filename minus its last "/"-component (its directory prefix).
    func remoteDir(of filename: String) -> String {
        let normalized = filename.replacingOccurrences(of: "\\", with: "/")
        guard let slash = normalized.lastIndex(of: "/") else { return normalized }
        return String(normalized[..<slash])
    }

    func appendingComponents(_ path: String, to base: URL, isDir: Bool) -> URL {
        var url = base
        let comps = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init)
        for (i, c) in comps.enumerated() {
            url = url.appendingPathComponent(c, isDirectory: isDir ? true : i < comps.count - 1)
        }
        return url
    }

    func fileMTime(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    func localFileMatchesRemote(_ url: URL, remote: CloudRemoteFile) -> Bool {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size == remote.size
        else { return false }
        return SHA1Digest.fileMatches(url, remoteDigest: remote.sha)
    }
}

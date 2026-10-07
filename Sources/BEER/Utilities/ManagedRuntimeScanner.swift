import Foundation

enum ManagedRuntimeScanner {
    static func findAll() -> [RuntimeCandidate] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: AppPaths.runtimesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children.compactMap { child in
            findRuntime(in: child, displayName: "Managed \(child.lastPathComponent)")
        }
    }

    static func findRuntime(in directory: URL, displayName: String) -> RuntimeCandidate? {
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }

        if let runtime = RuntimeBundle.candidateIfAvailable(in: directory, fallbackDisplayName: displayName) {
            return runtime
        }

        let preferredNames = ["gameportingtoolkit", "wine64", "wine"]
        var matches: [(String, URL)] = []

        if let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isExecutableKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                if let runtime = RuntimeBundle.candidateIfAvailable(in: url, fallbackDisplayName: displayName) {
                    return runtime
                }

                guard preferredNames.contains(url.lastPathComponent),
                      FileManager.default.isExecutableFile(atPath: url.path) else {
                    continue
                }
                matches.append((url.lastPathComponent, url))
            }
        }

        for name in preferredNames {
            let named = matches.filter { $0.0 == name }
            // Prefer a real Wine bin (has a sibling `wineserver`) over launcher
            // stubs like `Wine.app/Contents/MacOS/wine`, which can run a given
            // exe but can't resolve Wine's own tools (reg, wineboot, …).
            guard let match = named.first(where: { hasSiblingWineserver($0.1) }) ?? named.first else { continue }
            let kind: RuntimeKind = name == "gameportingtoolkit" ? .gamePortingToolkit : .systemWine
            let binDir = match.1.deletingLastPathComponent()
            func sibling(_ n: String) -> String? {
                let p = binDir.appendingPathComponent(n).path
                return FileManager.default.isExecutableFile(atPath: p) ? p : nil
            }
            let entrypoints = RuntimeEntrypoints(
                wine: match.1.path,
                wineboot: sibling("wineboot"),
                wineserver: sibling("wineserver")
            )
            return RuntimeCandidate(kind: kind, executablePath: match.1.path,
                                    displayName: displayName, entrypoints: entrypoints)
        }

        return nil
    }

    private static func hasSiblingWineserver(_ wineBinary: URL) -> Bool {
        let sibling = wineBinary.deletingLastPathComponent().appendingPathComponent("wineserver").path
        return FileManager.default.isExecutableFile(atPath: sibling)
    }
}

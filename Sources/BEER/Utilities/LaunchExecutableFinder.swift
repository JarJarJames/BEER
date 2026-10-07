import Foundation

enum LaunchExecutableFinder {
    /// Walk the install dir, find Windows `.exe` files, and pick the most
    /// likely main game executable. Heuristic:
    ///   1. Drop common installers / redists / crash handlers.
    ///   2. Prefer files whose basename contains the game name (letters-only compare).
    ///   3. Otherwise return the largest remaining .exe.
    static func find(in installDir: URL, gameName: String) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: installDir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            return nil
        }

        let skip = [
            "unins", "redist", "vcredist", "vc_redist", "directx", "dxsetup", "dotnet", "dotnetfx",
            "crashreport", "crashpad", "crashhandler", "uninstall", "uninstaller",
            "_setup", "setup", "installer", "report", "updater", "patch", "easyanticheat",
            "battleye", "anticheat"
        ]

        var candidates: [(url: URL, size: Int64, name: String)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "exe" else { continue }
            let lower = url.lastPathComponent.lowercased()
            if skip.contains(where: { lower.contains($0) }) { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            candidates.append((url, size, url.lastPathComponent))
        }

        let normalizedGame = gameName.lowercased().filter(\.isLetter)
        if normalizedGame.count > 2,
           let match = candidates.first(where: { $0.name.lowercased().filter(\.isLetter).contains(normalizedGame) }) {
            return match.url
        }
        return candidates.max(by: { $0.size < $1.size })?.url
    }
}

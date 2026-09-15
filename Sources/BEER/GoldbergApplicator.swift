import Foundation

// GoldbergApplicator drops the GBE_Fork Steamworks-emu stubs into a game's
// install tree so the game launches without a running Steam process.
//
// Per gbe_fork's README.release.md, the recipe for a single game is:
//   1. Replace each `steam_api.dll` (32-bit) and/or `steam_api64.dll`
//      (64-bit) in the install with the matching arch stub.
//   2. Drop a `steam_settings/` folder beside the stub that contains at
//      minimum a `steam_appid.txt` with the numeric Steam appID.
//
// DLC needs a third ingredient. The emulator answers GetDLCCount() /
// BGetDLCDataByIndex() from the `[app::dlcs]` block of `configs.app.ini`, so
// with no such file a game that *enumerates* its DLC finds none no matter what
// is on disk. We write that block from the bottle's enabled-DLC list.
//
// We do this recursively across the whole install dir because some games
// ship multiple copies (e.g. /redist, /tools, the main exe dir). For each
// patched DLL we keep the original at `<name>.original` so a Restore action
// can put everything back.

enum GoldbergPatchError: LocalizedError {
    case stubsMissing
    case unreadableInstallDir(String)
    case noSteamApiFound

    var errorDescription: String? {
        switch self {
        case .stubsMissing:
            return "The Steam emulator binaries weren't found. Reapply it from this game's settings."
        case .unreadableInstallDir(let path):
            return "Could not read the game's install directory at \(path)."
        case .noSteamApiFound:
            return "No steam_api.dll / steam_api64.dll was found in the install. Either the game doesn't use Steamworks, or the depot download is incomplete."
        }
    }
}

struct GoldbergPatchReport {
    var patched: [URL]      // .dll paths we replaced
    var backedUp: [URL]     // matching .original paths
    var settingsDirs: [URL] // steam_settings folders we created
    var alreadyPatched: Int // count of DLLs we found but had already swapped

    var totalPatched: Int { patched.count + alreadyPatched }
}

enum GoldbergApplicator {
    /// Walk the install dir and replace every steam_api*.dll with the matching
    /// GBE_Fork stub. Idempotent: re-running is safe and only patches DLLs we
    /// haven't already patched.
    @MainActor
    static func apply(installDir: URL, appID: Int, account: String? = nil, steamID64: String? = nil, dlc: [InstalledDLC] = [], using installer: GoldbergInstaller) throws -> GoldbergPatchReport {
        guard let stub64 = installer.steamApi64URL, let stub32 = installer.steamApi32URL else {
            throw GoldbergPatchError.stubsMissing
        }
        guard let dlls = findSteamApiDLLs(in: installDir) else {
            throw GoldbergPatchError.unreadableInstallDir(installDir.path)
        }
        guard !dlls.isEmpty else {
            throw GoldbergPatchError.noSteamApiFound
        }

        let fm = FileManager.default
        var report = GoldbergPatchReport(patched: [], backedUp: [], settingsDirs: [], alreadyPatched: 0)

        // Read the stub size once — we use it to detect "already patched"
        // (a file that's byte-identical to our stub is already swapped).
        let stub64Data = (try? Data(contentsOf: stub64)) ?? Data()
        let stub32Data = (try? Data(contentsOf: stub32)) ?? Data()

        for dll in dlls {
            let name = dll.lastPathComponent.lowercased()
            let isWide = name == "steam_api64.dll"
            let stubData = isWide ? stub64Data : stub32Data
            let stubURL = isWide ? stub64 : stub32

            // Idempotency check: byte-identical to the stub → already patched.
            if let existing = try? Data(contentsOf: dll), existing == stubData {
                report.alreadyPatched += 1
                // Still write the steam_settings folder in case it's missing.
                let settings = try writeSteamSettings(beside: dll, appID: appID, account: account, steamID64: steamID64, dlc: dlc, fileManager: fm)
                report.settingsDirs.append(settings)
                continue
            }

            // Back up the original (only if we haven't already).
            let backupURL = dll.appendingPathExtension("original")
            if !fm.fileExists(atPath: backupURL.path) {
                try fm.copyItem(at: dll, to: backupURL)
                report.backedUp.append(backupURL)
            }

            // Swap in the stub.
            if fm.fileExists(atPath: dll.path) {
                try fm.removeItem(at: dll)
            }
            try fm.copyItem(at: stubURL, to: dll)
            report.patched.append(dll)

            // Write steam_settings/steam_appid.txt beside it.
            let settings = try writeSteamSettings(beside: dll, appID: appID, account: account, steamID64: steamID64, dlc: dlc, fileManager: fm)
            report.settingsDirs.append(settings)
        }

        return report
    }

    /// Reverse an apply(): copy every `.original` back over the stub and
    /// delete any steam_settings dirs that contain only files we created.
    static func restore(installDir: URL) throws -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: installDir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return 0
        }
        var restored = 0
        for case let url as URL in enumerator
        where url.pathExtension.lowercased() == "original"
            && url.deletingPathExtension().pathExtension.lowercased() == "dll" {
            let original = url
            let liveDLL = url.deletingPathExtension()
            // Replace the stub with the original.
            if fm.fileExists(atPath: liveDLL.path) {
                try fm.removeItem(at: liveDLL)
            }
            try fm.moveItem(at: original, to: liveDLL)
            restored += 1

            // Remove our steam_settings folder if it's the simple one we wrote
            // (we'll only touch a folder that contains just steam_appid.txt;
            // leave anything richer alone in case the user customized it).
            let settingsDir = liveDLL.deletingLastPathComponent().appendingPathComponent("steam_settings", isDirectory: true)
            let ours: Set<String> = ["steam_appid.txt", "configs.user.ini", "configs.app.ini"]
            if let entries = try? fm.contentsOfDirectory(atPath: settingsDir.path),
               entries.allSatisfy({ ours.contains($0) || $0.hasPrefix(".") }) {
                try? fm.removeItem(at: settingsDir)
            }
        }
        return restored
    }

    // MARK: - DLC

    /// Rewrite the `[app::dlcs]` block in every steam_settings folder already
    /// present under `installDir`, without touching the patched DLLs. Lets the
    /// DLC manager change what the game is told it owns without a re-patch.
    /// Returns the number of folders updated.
    @discardableResult
    static func updateDLC(installDir: URL, dlc: [InstalledDLC]) throws -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: installDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw GoldbergPatchError.unreadableInstallDir(installDir.path)
        }
        var updated = 0
        for case let url as URL in enumerator where url.lastPathComponent == "steam_settings" {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            try writeDLCSection(in: url, dlc: dlc, fileManager: fm)
            updated += 1
        }
        return updated
    }

    /// Splice our `[app::dlcs]` block into `configs.app.ini`, leaving any other
    /// section the user may have added alone. With no DLC the block is removed,
    /// and the file deleted if that leaves it empty — so turning every DLC off
    /// restores the emulator's stock behaviour rather than pinning an empty list.
    private static func writeDLCSection(in settingsDir: URL, dlc: [InstalledDLC], fileManager fm: FileManager) throws {
        let configURL = settingsDir.appendingPathComponent("configs.app.ini", isDirectory: false)
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        var kept = stripDLCSection(from: existing)

        if !dlc.isEmpty {
            var section = "[app::dlcs]\n"
            // unlock_all=0 with an explicit list, not 1: gbe_fork's own docs note
            // that some games probe for a made-up DLC id to detect an emulator,
            // and blanket-unlocking answers yes to those too.
            section += "unlock_all=0\n"
            for item in dlc.sorted(by: { $0.appID < $1.appID }) {
                section += "\(item.appID)=\(item.iniSafeName)\n"
            }
            if !kept.isEmpty && !kept.hasSuffix("\n\n") {
                kept += kept.hasSuffix("\n") ? "\n" : "\n\n"
            }
            kept += section
        }

        if kept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if fm.fileExists(atPath: configURL.path) {
                try fm.removeItem(at: configURL)
            }
            return
        }
        try kept.write(to: configURL, atomically: true, encoding: .utf8)
    }

    /// Drop the `[app::dlcs]` section from an ini, keeping every other section.
    private static func stripDLCSection(from contents: String) -> String {
        guard !contents.isEmpty else { return "" }
        var out: [Substring] = []
        var inDLCSection = false
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inDLCSection = trimmed.lowercased() == "[app::dlcs]"
            }
            if !inDLCSection { out.append(line) }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    // MARK: - Internals

    private static func findSteamApiDLLs(in installDir: URL) -> [URL]? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: installDir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return nil
        }
        var found: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent.lowercased()
            if name == "steam_api.dll" || name == "steam_api64.dll" {
                found.append(url)
            }
        }
        return found
    }

    private static func writeSteamSettings(beside dll: URL, appID: Int, account: String?, steamID64: String?, dlc: [InstalledDLC], fileManager fm: FileManager) throws -> URL {
        let settingsDir = dll.deletingLastPathComponent().appendingPathComponent("steam_settings", isDirectory: true)
        try fm.createDirectory(at: settingsDir, withIntermediateDirectories: true)
        let appidFile = settingsDir.appendingPathComponent("steam_appid.txt", isDirectory: false)
        try String(appID).write(to: appidFile, atomically: true, encoding: .utf8)

        // Tell the emulator to present the user's REAL Steam identity, so games
        // that key saves/profiles to the SteamID recognize their existing data
        // instead of starting fresh under the emulator's default account.
        if let steamID64, !steamID64.isEmpty, steamID64 != "0" {
            var ini = "[user::general]\n"
            if let account, !account.isEmpty { ini += "account_name=\(account)\n" }
            ini += "account_steamid=\(steamID64)\n"
            let userConfig = settingsDir.appendingPathComponent("configs.user.ini", isDirectory: false)
            try ini.write(to: userConfig, atomically: true, encoding: .utf8)
        }

        try writeDLCSection(in: settingsDir, dlc: dlc, fileManager: fm)
        return settingsDir
    }
}

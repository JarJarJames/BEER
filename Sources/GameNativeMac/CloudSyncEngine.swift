import Foundation

// Bridges Steam Cloud (via SteamCloud's web-scrape client) and a bottle's
// Wine prefix. Pulls remote saves down into the right Wine user-home
// subdirectory based on the file's Steam-Cloud folder tag.
//
// Push is intentionally unimplemented: Valve doesn't expose a third-party
// cloud upload API. We throw .uploadNotSupported from push() and surface
// that to the user instead of silently no-opping.

struct CloudSyncReport {
    var downloaded: Int = 0
    var skipped: Int = 0
    var failures: [(filename: String, reason: String)] = []
}

enum CloudSyncError: LocalizedError {
    case userHomeNotFound(URL)
    case noFiles

    var errorDescription: String? {
        switch self {
        case .userHomeNotFound(let url):
            return "Couldn't find a Wine user home inside \(url.path). The bottle may not be initialized."
        case .noFiles:
            return "Steam has no cloud files for this game on your account."
        }
    }
}

/// Maps Steam-Cloud "folder" tags to relative paths inside the Wine prefix's
/// user home (drive_c/users/<user>/). These are stable — Steam picks one of
/// a small set of well-known roots for each save category.
private let steamFolderRouting: [String: String] = [
    "WinSavedGames": "Saved Games",
    "WinAppDataRoaming": "AppData/Roaming",
    "WinAppDataLocal": "AppData/Local",
    "WinAppDataLocalLow": "AppData/LocalLow",
    "WinDocuments": "Documents",
    "WinMyDocuments": "Documents",
    "WinMyPictures": "Pictures",
    "WinMyMusic": "Music",
    "WinMyVideo": "Videos"
]

@MainActor
final class CloudSyncEngine: ObservableObject {
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var phase: String = ""
    @Published private(set) var lastSyncAt: Date? = nil
    @Published private(set) var lastReport: CloudSyncReport? = nil
    @Published var lastError: String? = nil

    private let cloud = SteamCloud()

    // MARK: - Pull

    /// Pull every Steam Cloud file for this game down into the bottle.
    /// Skips files where the local copy is mtime-equal-or-newer.
    func pull(bottle: Bottle, appID: Int, auth: SteamAuthStore) async throws -> CloudSyncReport {
        isSyncing = true
        defer { isSyncing = false }

        phase = "Exchanging refresh token for web session…"
        try await auth.ensureWebSession()

        phase = "Listing cloud files…"
        let files = try await cloud.enumerateUserFiles(appID: appID)
        guard !files.isEmpty else {
            phase = "No cloud files for this game on your account."
            lastSyncAt = Date()
            let r = CloudSyncReport()
            lastReport = r
            return r
        }

        let userHome = try resolveWineUserHome(for: bottle)
        var report = CloudSyncReport()

        for file in files {
            phase = "Pulling \(file.displayPath)…"
            let target = mapToLocal(file, userHome: userHome)

            if let attrs = try? FileManager.default.attributesOfItem(atPath: target.path),
               let mtime = attrs[.modificationDate] as? Date,
               mtime >= file.timestamp {
                report.skipped += 1
                continue
            }

            do {
                let bytes = try await cloud.download(file: file)
                try FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try bytes.write(to: target, options: .atomic)
                try? FileManager.default.setAttributes(
                    [.modificationDate: file.timestamp],
                    ofItemAtPath: target.path
                )
                report.downloaded += 1
            } catch {
                report.failures.append((file.displayPath, error.localizedDescription))
            }
        }

        lastSyncAt = Date()
        lastReport = report
        phase = "Pull complete — \(report.downloaded) downloaded, \(report.skipped) up-to-date" +
                (report.failures.isEmpty ? "." : ", \(report.failures.count) failed.")
        return report
    }

    // MARK: - Push (not supported)

    /// Steam doesn't expose an upload API to non-publishers, and a fake
    /// Steam.exe (Goldberg) can't push to real cloud either. We surface
    /// this clearly rather than silently no-op.
    func push(bottle: Bottle, appID: Int, auth: SteamAuthStore) async throws -> CloudSyncReport {
        throw SteamCloudError.uploadNotSupported
    }

    // MARK: - Path mapping

    /// Find the wine user home for this bottle:
    /// `<bottle>/drive_c/users/<some-user>/`. Wine initializes one when
    /// wineboot first runs.
    private func resolveWineUserHome(for bottle: Bottle) throws -> URL {
        let usersDir = AppPaths.prefixURL(for: bottle)
            .appendingPathComponent("drive_c", isDirectory: true)
            .appendingPathComponent("users", isDirectory: true)
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: usersDir.path)) ?? []
        let candidate = entries
            .filter { !$0.hasPrefix(".") }
            .first(where: { $0 != "Public" })
            ?? entries.first
        guard let user = candidate else {
            throw CloudSyncError.userHomeNotFound(usersDir)
        }
        return usersDir.appendingPathComponent(user, isDirectory: true)
    }

    /// Given a Steam cloud file, where does it belong on disk?
    private func mapToLocal(_ file: CloudFile, userHome: URL) -> URL {
        // Folder tag → relative path under user home.
        let folderPath = steamFolderRouting[file.folder] ?? file.folder
        var url = userHome
        for component in folderPath.split(whereSeparator: { $0 == "/" || $0 == "\\" }) {
            url = url.appendingPathComponent(String(component), isDirectory: true)
        }
        for component in file.relativePath.split(whereSeparator: { $0 == "/" || $0 == "\\" }) {
            url = url.appendingPathComponent(String(component), isDirectory: false)
        }
        return url
    }
}

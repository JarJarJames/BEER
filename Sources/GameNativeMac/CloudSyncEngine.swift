import Foundation

// Bridges Steam Cloud and a bottle's Wine prefix.
//
// Cloud file paths from Steam come back as forward-slash-separated paths
// keyed off the user's Windows home (e.g. "Saved Games/Kingdom Come
// Deliverance/saves/foo.whs"). Wine maps %USERPROFILE% to
// <bottle>/drive_c/users/<MAC_USER>/, so the mapping is straightforward.
//
// Sync policy: newer-mtime-wins on either side. Files that exist only in
// one place flow to the other.
//
// First-time pull discovers the relative directories the game uses; we
// remember them per-bottle so subsequent pushes can re-walk the same
// directories looking for new local saves.

struct CloudSyncReport {
    var downloaded: Int = 0
    var uploaded: Int = 0
    var skipped: Int = 0
    var failures: [(filename: String, reason: String)] = []
}

enum CloudSyncError: LocalizedError {
    case userHomeNotFound(URL)

    var errorDescription: String? {
        switch self {
        case .userHomeNotFound(let url):
            return "Couldn't find a Wine user home inside \(url.path). The bottle may not be initialized."
        }
    }
}

@MainActor
final class CloudSyncEngine: ObservableObject {
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var phase: String = ""
    @Published private(set) var lastSyncAt: Date? = nil
    @Published private(set) var lastReport: CloudSyncReport? = nil
    @Published var lastError: String? = nil

    private let cloud = SteamCloud()

    // Per-bottle: which top-level directories under the wine user home did
    // we see cloud files in? Used for push to know where to look.
    private var trackedDirectories: [UUID: Set<String>] = [:]

    // MARK: - Pull (cloud → local)

    /// Pull every Steam Cloud file for this game down into the bottle.
    /// Local files newer than the cloud counterpart are skipped.
    func pull(bottle: Bottle, appID: Int, auth: SteamAuthStore) async throws -> CloudSyncReport {
        isSyncing = true
        defer { isSyncing = false }

        phase = "Refreshing access token…"
        let token = try await auth.getAccessToken()

        phase = "Listing cloud files…"
        let files = try await cloud.enumerateUserFiles(appID: appID, accessToken: token)
        if files.isEmpty {
            phase = "Steam Cloud has no files for this game yet."
            lastSyncAt = Date()
            let r = CloudSyncReport()
            lastReport = r
            return r
        }

        let userHome = try resolveWineUserHome(for: bottle)
        var report = CloudSyncReport()
        var seenDirs = Set<String>()

        for file in files {
            phase = "Pulling \(file.filename)…"
            let target = mapCloudPathToLocal(cloudPath: file.filename, userHome: userHome)

            if let topDir = file.filename.split(separator: "/").first.map(String.init) {
                seenDirs.insert(topDir)
            }

            // Skip if our local copy is newer-or-equal.
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
                report.failures.append((file.filename, error.localizedDescription))
            }
        }

        trackedDirectories[bottle.id] = seenDirs
        lastSyncAt = Date()
        lastReport = report
        phase = "Pull complete — \(report.downloaded) downloaded, \(report.skipped) up-to-date" +
                (report.failures.isEmpty ? "." : ", \(report.failures.count) failed.")
        return report
    }

    // MARK: - Push (local → cloud)

    /// Push any local files that are newer than their cloud counterpart, or
    /// that exist locally but not in cloud, up to Steam Cloud.
    ///
    /// To avoid uploading the entire bottle, we only walk the top-level
    /// directories that we saw cloud files in during the last pull
    /// (e.g. "Saved Games" for KCD). Pull-first-then-push is the expected
    /// workflow; a fresh push without a prior pull will no-op.
    func push(bottle: Bottle, appID: Int, auth: SteamAuthStore) async throws -> CloudSyncReport {
        isSyncing = true
        defer { isSyncing = false }

        phase = "Refreshing access token…"
        let token = try await auth.getAccessToken()

        phase = "Listing cloud files for comparison…"
        let cloudFiles = try await cloud.enumerateUserFiles(appID: appID, accessToken: token)
        let cloudByName: [String: CloudFile] = Dictionary(
            cloudFiles.map { ($0.filename.lowercased(), $0) },
            uniquingKeysWith: { a, _ in a }
        )

        let userHome = try resolveWineUserHome(for: bottle)
        var directories = trackedDirectories[bottle.id] ?? []
        // If we never pulled, learn directory hints from cloud listing.
        if directories.isEmpty {
            for f in cloudFiles {
                if let top = f.filename.split(separator: "/").first.map(String.init) {
                    directories.insert(top)
                }
            }
        }

        var report = CloudSyncReport()

        // Collect file URLs synchronously (FileManager.enumerator isn't
        // safe to drive across `await` suspension points under strict
        // concurrency — it's non-Sendable).
        let candidates: [URL] = directories.flatMap { dir -> [URL] in
            let root = userHome.appendingPathComponent(dir, isDirectory: true)
            guard FileManager.default.fileExists(atPath: root.path) else { return [] }
            guard let walker = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]
            ) else { return [] }
            var collected: [URL] = []
            for case let url as URL in walker {
                let rv = try? url.resourceValues(forKeys: [.isRegularFileKey])
                if rv?.isRegularFile == true {
                    collected.append(url)
                }
            }
            return collected
        }

        for url in candidates {
            let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let localMtime = rv?.contentModificationDate else { continue }

            let cloudPath = relativeCloudPath(for: url, userHome: userHome)
            phase = "Pushing \(cloudPath)…"

            // Skip if Steam already has this file at >= mtime.
            if let existing = cloudByName[cloudPath.lowercased()],
               existing.timestamp >= localMtime {
                report.skipped += 1
                continue
            }

            do {
                let data = try Data(contentsOf: url)
                let handle = try await cloud.beginUpload(
                    appID: appID,
                    filename: cloudPath,
                    data: data,
                    accessToken: token
                )
                try await cloud.putBytes(data, to: handle)
                try await cloud.commitUpload(handle, succeeded: true, accessToken: token)
                report.uploaded += 1
            } catch {
                report.failures.append((cloudPath, error.localizedDescription))
            }
        }

        lastSyncAt = Date()
        lastReport = report
        phase = "Push complete — \(report.uploaded) uploaded, \(report.skipped) up-to-date" +
                (report.failures.isEmpty ? "." : ", \(report.failures.count) failed.")
        return report
    }

    // MARK: - Path mapping

    /// Find the wine user home for this bottle:
    /// `<bottle>/drive_c/users/<some-user>/`. Wine creates one per prefix,
    /// usually named after the macOS short user, but historic prefixes may
    /// have a different name. We pick the first non-Public entry.
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

    /// Steam Cloud filenames are paths relative to %USERPROFILE% on Windows.
    /// Wine's %USERPROFILE% maps to drive_c/users/<user>/, so we just
    /// resolve the components against that root.
    private func mapCloudPathToLocal(cloudPath: String, userHome: URL) -> URL {
        let cleaned = cloudPath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var url = userHome
        for component in cleaned.split(separator: "/") {
            url = url.appendingPathComponent(String(component), isDirectory: false)
        }
        return url
    }

    /// Inverse of mapCloudPathToLocal: produce a cloud-style relative path
    /// from an absolute URL inside the wine user home. Returns "" if the
    /// URL isn't inside `userHome`.
    private func relativeCloudPath(for localURL: URL, userHome: URL) -> String {
        let homePath = userHome.path + "/"
        guard localURL.path.hasPrefix(homePath) else {
            return localURL.lastPathComponent
        }
        return String(localURL.path.dropFirst(homePath.count))
    }
}

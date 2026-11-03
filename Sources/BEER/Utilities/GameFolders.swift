import Foundation

/// Rules for game folders on drives: naming them, refusing to write to a drive
/// that isn't there, and deciding which folders are BEER's to delete.
enum GameFolders {
    /// Suffix of a folder a move is still copying into. Never launched from.
    static let stagingSuffix = ".beer-moving"

    /// `/Volumes/<name>` for a path on a drive; nil for a path on this Mac.
    static func driveRoot(of url: URL) -> URL? {
        let components = url.standardizedFileURL.pathComponents
        guard components.count >= 3, components[0] == "/", components[1] == "Volumes" else { return nil }
        return URL(fileURLWithPath: "/Volumes/\(components[2])", isDirectory: true)
    }

    /// Whether `root` is a mounted volume, not a plain folder that happens to
    /// sit in /Volumes. Where /Volumes is writable, writing under an unplugged
    /// drive's old path creates such a folder on the Mac's own disk, and macOS
    /// then mounts the drive as "<name> 1" beside it.
    static func isMounted(_ root: URL) -> Bool {
        // A missing path has no resource values; it isn't mounted.
        (try? root.resourceValues(forKeys: [.isVolumeKey]))?.isVolume == true
    }

    /// Throws when `url` is on a drive that isn't mounted. Call it before
    /// creating anything on a drive, so the player is told the drive is
    /// missing instead of seeing a permissions error.
    static func requireDrive(for url: URL) throws {
        guard let root = driveRoot(of: url) else { return }
        guard isMounted(root) else { throw GameFolderError.driveNotConnected(root.lastPathComponent) }
    }

    /// Whether `drive` is plugged in (by ID, whatever it's called now).
    static func isConnected(_ drive: GameDrive, volumes: VolumeCatalog) -> Bool {
        volumes.drive(withUUID: drive.uuid) != nil
    }

    /// A folder for `name` in `parent` that nothing else is using. Anything
    /// already there, even a leftover of the same game, gets a numbered name:
    /// one game never lands in another's folder, and an install never adopts
    /// a folder whose saves a cancelled install would then delete. Leftovers
    /// are offered back through the found-games list instead.
    static func freeFolder(for name: String, in parent: URL) -> URL {
        let fm = FileManager.default
        let base = name.safeGameFolderName
        for number in 1...GameFolderLimits.maxNumberedNames {
            let candidate = parent.appendingPathComponent(number == 1 ? base : "\(base) \(number)", isDirectory: true)
            if !fm.fileExists(atPath: candidate.path), !fm.fileExists(atPath: stagingFolder(for: candidate).path) {
                return candidate
            }
        }
        return parent.appendingPathComponent("\(base) \(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    static func stagingFolder(for folder: URL) -> URL {
        folder.deletingLastPathComponent()
            .appendingPathComponent(folder.lastPathComponent + stagingSuffix, isDirectory: true)
    }

    /// Whether `folder` sits directly inside one of `parents`. BEER only ever
    /// deletes a game folder that passes this for its own `Games` folders,
    /// never a path just because a bottle has it stored.
    static func isDirectChild(_ folder: URL, ofAny parents: [URL]) -> Bool {
        let parent = canonicalPath(folder.deletingLastPathComponent())
        return !folder.lastPathComponent.isEmpty && parents.contains { canonicalPath($0) == parent }
    }

    static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// The folder on a drive that uninstalling `bottle` should delete besides
    /// the bottle itself. Nil unless the drive is connected (and is the same
    /// drive, by ID), the folder is directly in that drive's `BEER/Games`, and
    /// no other bottle uses it.
    static func driveFolderToDelete(for bottle: Bottle, among bottles: [Bottle], volumes: VolumeCatalog) -> URL? {
        guard let drive = bottle.gameDrive,
              let folder = bottle.installLocation(volumes: volumes).url,
              let mounted = volumes.drive(withUUID: drive.uuid),
              isDirectChild(folder, ofAny: [AppPaths.driveGamesDirectory(onDriveAt: mounted.root)]) else { return nil }
        let path = canonicalPath(folder)
        let shared = bottles.contains {
            $0.id != bottle.id && $0.installLocation(volumes: volumes).url.map(canonicalPath) == path
        }
        return shared ? nil : folder
    }
}

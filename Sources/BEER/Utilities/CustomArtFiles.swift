import Foundation

/// Copies art the player picks into BEER's own folder, so it survives the
/// original being moved or deleted.
enum CustomArtFiles {
    /// Each copy gets a new name (the time is in it), so an image view showing
    /// the old file can't keep showing it from cache after a change.
    static func copy(
        _ source: URL, appID: Int, slot: GameArtSlot,
        into directory: URL = AppPaths.customArtDirectory, now: Date = .now
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = source.pathExtension.lowercased().ifEmpty(default: "png")
        let target = directory.appendingPathComponent(
            "app\(appID)-\(slot.rawValue)-\(Int(now.timeIntervalSince1970)).\(ext)"
        )
        try? fm.removeItem(at: target)
        try fm.copyItem(at: source, to: target)
        return target
    }

    /// Removes a copy BEER made. Never touches a file outside `directory`.
    static func remove(path: String, in directory: URL = AppPaths.customArtDirectory) {
        let file = URL(fileURLWithPath: path).standardizedFileURL
        guard file.deletingLastPathComponent().path == directory.standardizedFileURL.path else { return }
        try? FileManager.default.removeItem(at: file)
    }
}

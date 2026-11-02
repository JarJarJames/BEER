import Foundation

/// One snapshot folder in a game's CloudSaveBackups, as the backups list
/// shows it.
struct CloudSaveSnapshot: Identifiable, Equatable {
    let url: URL
    let date: Date
    /// What took it: `before-sync`, `before-pull`, `before-clear`, …
    let label: String
    let fileCount: Int
    let byteCount: Int64

    var id: String { url.lastPathComponent }
}

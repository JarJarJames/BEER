import Foundation

/// What restoring a snapshot would do, worked out before anything is touched
/// so the confirmation can say it plainly.
struct SaveRestorePlan: Equatable {
    struct Folder: Equatable {
        /// The copy inside the snapshot.
        let stored: URL
        /// The save folder it goes back to.
        let target: URL
    }

    let snapshot: CloudSaveSnapshot
    let folders: [Folder]
    /// Files the restore puts in place.
    let filesRestored: Int
    /// Files there now that the snapshot doesn't have, which the restore removes.
    let filesRemoved: Int
    /// When the current saves were last changed. Nil when there are none.
    let currentLastChanged: Date?
}

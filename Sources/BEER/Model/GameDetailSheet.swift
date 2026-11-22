import Foundation

/// The sheet the game page shows. Only one is up at a time: opening another
/// replaces it, and nil closes it.
enum GameDetailSheet: Identifiable, Equatable {
    case artwork
    case cloudConnect
    case install
    case move
    case shortcutIcon
    /// `confirmingRestore` is set while the sheet asks before a restore.
    case saveBackups(confirmingRestore: SaveRestorePlan?)
    case restoreConflict(RestoreConflictPrompt)
    case dlcManager

    var id: String {
        switch self {
        case .artwork: "artwork"
        case .cloudConnect: "cloudConnect"
        case .install: "install"
        case .move: "move"
        case .shortcutIcon: "shortcutIcon"
        // The same sheet whether or not it's asking, so asking doesn't reopen it.
        case .saveBackups: "saveBackups"
        case .restoreConflict(let prompt): "restoreConflict-\(prompt.id)"
        case .dlcManager: "dlcManager"
        }
    }
}

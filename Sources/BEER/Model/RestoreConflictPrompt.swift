import Foundation

/// A sync that stopped on a restored backup, held until the player chooses.
/// `retry` is what they were doing, run again once they have.
struct RestoreConflictPrompt: Identifiable {
    enum Retry {
        case sync(pull: Bool, push: Bool)
        case launch
    }

    let id = UUID()
    let conflict: SaveRestoreConflict
    let bottle: Bottle
    let retry: Retry
}

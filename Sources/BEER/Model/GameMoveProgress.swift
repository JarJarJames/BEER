import Foundation

/// How far a move has got, for the progress bar on the game page.
struct GameMoveProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case copying
        case checking
        case finishing
    }

    var phase: Phase
    var copiedBytes: Int64
    var totalBytes: Int64

    var fraction: Double {
        totalBytes > 0 ? Double(copiedBytes) / Double(totalBytes) : 0
    }

    var label: String {
        switch phase {
        case .copying: return GameMoveStrings.copying(copiedBytes, of: totalBytes)
        case .checking: return GameMoveStrings.checking
        case .finishing: return GameMoveStrings.finishing
        }
    }
}

/// How a move ended.
enum GameMoveOutcome: Equatable, Sendable {
    case moved
    /// The game runs from its new place, but its old copy is still there.
    case movedKeptOldCopy(reason: String)
}

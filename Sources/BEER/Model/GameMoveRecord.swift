import Foundation

/// A move between drives that hasn't finished, as written to the move journal.
/// Enough to undo or complete it after BEER quits or a drive is pulled partway.
struct GameMoveRecord: Codable, Equatable, Sendable {
    enum Stage: String, Codable, Sendable {
        /// Copying into the staging folder. The game still runs from `source`.
        case copying
        /// The bottle points at `destination`; `source` is the old copy.
        case switched
    }

    var bottleID: UUID
    var source: String
    var sourceDrive: GameDrive?
    var destination: String
    var destinationDrive: GameDrive?
    var stage: Stage

    var sourceURL: URL { URL(fileURLWithPath: source, isDirectory: true) }
    var destinationURL: URL { URL(fileURLWithPath: destination, isDirectory: true) }
    var stagingURL: URL { GameFolders.stagingFolder(for: destinationURL) }
}

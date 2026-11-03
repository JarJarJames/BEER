import Foundation

/// The small file BEER keeps in every game folder (`.beer-game.json`), saying
/// which game it holds. Lets a folder be recognized on its own: after a move,
/// on a drive plugged into another Mac, or after its bottle was removed.
struct GameFolderMarker: Codable, Equatable, Sendable {
    static let fileName = ".beer-game.json"

    /// Nil for a non-Steam game: its placeholder ID only means something inside
    /// the BEER that made it.
    var appID: Int?
    var name: String
    var isNonSteam: Bool
    /// The launch .exe, relative to the game folder.
    var launchExecutable: String?
}

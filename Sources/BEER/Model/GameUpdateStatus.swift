import Foundation

/// Whether an installed game matches what Steam serves, as the CloudSync
/// helper's `updatecheck` reports it.
enum GameUpdateStatus: String, Codable {
    case current
    case update
    /// The game's folder has no DepotDownloader record to compare, as with an
    /// install from an older BEER. One Reinstall / Validate writes it.
    case untracked
    /// Steam has no info on the game. Never stored: the last answer stands.
    case unknown
}

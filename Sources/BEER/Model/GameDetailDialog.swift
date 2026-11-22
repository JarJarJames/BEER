import Foundation

/// The confirmation or alert the game page shows. Only one is up at a time,
/// and nil closes it.
enum GameDetailDialog: Equatable {
    /// Play found a newer build: update first, or play this one.
    case updateBeforePlay(Bottle)
    /// Removing a non-Steam game deletes the only folder BEER has for it.
    case removeNonSteamGame
    /// The game's drive isn't connected, so removing it leaves its files there.
    case removeWithDriveMissing
    /// Back up, then clear the bottle's local saves.
    case clearLocalSaves(Bottle)
    /// An install was refused because the disk can't hold it. Shown as an
    /// alert; the rest are confirmations.
    case diskSpaceShortfall(DiskSpaceShortfall)

    var shortfall: DiskSpaceShortfall? {
        if case .diskSpaceShortfall(let shortfall) = self { shortfall } else { nil }
    }
}

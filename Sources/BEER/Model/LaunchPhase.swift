import Foundation

/// Where a Play click has got to, shown in place of the Play button and on the
/// library card. Set by `BottleStore.runLaunch`; nil once the game's Wine
/// session has ended normally.
enum LaunchPhase: Equatable {
    /// The prefix, Steam's launch config, the client loader, the graphics
    /// translator.
    case settingUpWine
    /// The pre-launch Steam Cloud pull.
    case syncingSaves
    /// Redistributables, controllers and display mode, then the game's .exe
    /// until its first window shows. `isSlow` once that has taken long enough
    /// to point the player at the log.
    case startingGame(isSlow: Bool)
    /// A window in the bottle is on screen.
    case playing
    /// A step failed; the launch stopped here.
    case failed(String)

    /// False once the launch has failed, so Play comes back to try again.
    var isInProgress: Bool {
        if case .failed = self { return false }
        return true
    }

    var title: String {
        switch self {
        case .settingUpWine: return LaunchStatusStrings.settingUpWine
        case .syncingSaves: return LaunchStatusStrings.syncingSaves
        case .startingGame: return LaunchStatusStrings.startingGame
        case .playing: return LaunchStatusStrings.playing
        case .failed(let message): return message
        }
    }

    var cardText: String {
        switch self {
        case .settingUpWine: return LaunchStatusStrings.cardSettingUpWine
        case .syncingSaves: return LaunchStatusStrings.cardSyncingSaves
        case .startingGame: return LaunchStatusStrings.cardStartingGame
        case .playing: return LaunchStatusStrings.cardPlaying
        case .failed: return LaunchStatusStrings.cardFailed
        }
    }

    /// For a narrow card, in place of the words.
    var symbol: String {
        switch self {
        case .settingUpWine: return "gearshape.fill"
        case .syncingSaves: return "arrow.triangle.2.circlepath"
        case .startingGame: return "hourglass"
        case .playing: return "gamecontroller.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

import Foundation

/// The line under a game's name in the library.
enum LibraryCaption: String, CaseIterable, Identifiable {
    case appID
    case playtime
    case lastPlayed
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appID: "App ID"
        case .playtime: "Play time"
        case .lastPlayed: "Last played"
        case .none: "Nothing"
        }
    }

    /// Nil when the caption is turned off. Steam doesn't track non-Steam
    /// games, so those say so rather than claiming they were never played.
    func text(for game: SteamLibraryGame, playtime: PlaytimeFormat = .decimalHours,
              lastPlayed: LastPlayedFormat = .date, now: Date = .now) -> String? {
        switch self {
        case .appID:
            return game.effectiveIsNonSteam ? "Non-Steam" : "appID \(game.appID)"
        case .playtime:
            if let minutes = game.playtimeMinutes, minutes > 0 { return playtime.text(minutes: minutes) }
            return game.effectiveIsNonSteam ? "Non-Steam" : "Never played"
        case .lastPlayed:
            if let date = game.lastPlayed {
                return "Last played: \(lastPlayed.text(date, now: now))"
            }
            return game.effectiveIsNonSteam ? "Non-Steam" : "Never played"
        case .none:
            return nil
        }
    }
}

import Foundation

/// What shows under each game's art in the library: the name with one more
/// fact, the name alone, or nothing. List rows always show the name.
enum LibraryCardLabel: String, CaseIterable, Identifiable {
    case appID
    case playtime
    case lastPlayed
    case nameOnly
    /// Wide and Cover cards show the art alone, with the name on hover.
    case artOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appID: "Name and app ID"
        case .playtime: "Name and play time"
        case .lastPlayed: "Name and last played"
        case .nameOnly: "Name only"
        case .artOnly: "Nothing (art only)"
        }
    }

    var showsName: Bool { self != .artOnly }

    /// The line under the name; nil when there isn't one. Steam doesn't track
    /// non-Steam games, so those say so rather than claiming they were never
    /// played.
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
        case .nameOnly, .artOnly:
            return nil
        }
    }
}

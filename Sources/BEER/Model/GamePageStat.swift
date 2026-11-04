import Foundation

/// The facts a game's page can show, in the order it shows them.
enum GamePageStat: String, CaseIterable, Identifiable {
    case appID
    case lastPlayed
    case playtime
    case size

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appID: "App ID"
        case .lastPlayed: "Last played"
        case .playtime: "Play time"
        case .size: "Size on disk"
        }
    }

    /// What the page showed before the stats could be picked.
    static let defaultShown: Set<GamePageStat> = [.appID, .playtime]

    /// The stored list, as written by `encode`. Unknown names are skipped.
    static func decode(_ stored: String) -> Set<GamePageStat> {
        Set(stored.split(separator: ",").compactMap { GamePageStat(rawValue: String($0)) })
    }

    static func encode(_ stats: Set<GamePageStat>) -> String {
        allCases.filter(stats.contains).map(\.rawValue).joined(separator: ",")
    }

    /// The shown facts this game has a value for. A game Steam never saw
    /// played has no play time; the size is nil until measured.
    static func stats(
        _ shown: Set<GamePageStat>, for game: SteamLibraryGame, installedBytes: Int64?,
        playtime: PlaytimeFormat, lastPlayed: LastPlayedFormat, now: Date = .now
    ) -> [GameStat] {
        allCases.filter(shown.contains).compactMap { stat in
            switch stat {
            case .appID:
                return game.effectiveIsNonSteam
                    ? GameStat(title: "TYPE", value: "Non-Steam", inline: "Non-Steam", systemImage: "gamecontroller")
                    : GameStat(title: "APP ID", value: "\(game.appID)", inline: "appID \(game.appID)", systemImage: "number")
            case .lastPlayed:
                // Steam doesn't track non-Steam games, so "never" would be wrong.
                if game.effectiveIsNonSteam && game.lastPlayed == nil { return nil }
                let value = game.lastPlayed.map { lastPlayed.text($0, now: now) } ?? "Never"
                return GameStat(title: "LAST PLAYED", value: value,
                                inline: game.lastPlayed == nil ? "Never played" : "Last played \(value)",
                                systemImage: "calendar")
            case .playtime:
                guard let minutes = game.playtimeMinutes, minutes > 0 else { return nil }
                let value = playtime.text(minutes: minutes)
                return GameStat(title: "PLAY TIME", value: value, inline: value, systemImage: "clock")
            case .size:
                guard let bytes = installedBytes else { return nil }
                return GameStat(title: "SIZE ON DISK", value: bytes.fileSizeString,
                                inline: "\(bytes.fileSizeString) on disk", systemImage: "internaldrive")
            }
        }
    }
}

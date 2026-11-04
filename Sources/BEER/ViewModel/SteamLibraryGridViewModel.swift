import Foundation

/// Search text plus the filtering and ordering rules for the library grid.
/// The rules are pure functions of the games and the set of installed bottles,
/// so they can be tested without any store.
@MainActor
final class SteamLibraryGridViewModel: ObservableObject {
    @Published var searchText: String = ""

    func isInstalled(_ game: SteamLibraryGame, installedBottleIDs: Set<UUID>) -> Bool {
        guard let bottleID = game.installedBottleID else { return false }
        return installedBottleIDs.contains(bottleID)
    }

    func installedCount(in games: [SteamLibraryGame], installedBottleIDs: Set<UUID>) -> Int {
        games.filter { isInstalled($0, installedBottleIDs: installedBottleIDs) }.count
    }

    func filteredGames(
        from games: [SteamLibraryGame],
        installedBottleIDs: Set<UUID>,
        installedOnly: Bool,
        sortOrder: LibrarySortOrder
    ) -> [SteamLibraryGame] {
        var base = installedOnly
            ? games.filter { isInstalled($0, installedBottleIDs: installedBottleIDs) }
            : games

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            base = base.filter { $0.name.lowercased().contains(q) || String($0.appID).contains(q) }
        }

        return base.sorted { a, b in
            switch sortOrder {
            case .installedFirst:
                // So the handful you've installed are always at the top of a
                // 300-game library.
                let ai = isInstalled(a, installedBottleIDs: installedBottleIDs)
                let bi = isInstalled(b, installedBottleIDs: installedBottleIDs)
                if ai != bi { return ai }
            case .name:
                break
            case .recentlyPlayed:
                // Never-played games go last.
                let ad = a.lastPlayed ?? .distantPast, bd = b.lastPlayed ?? .distantPast
                if ad != bd { return ad > bd }
            case .mostPlayed:
                let am = a.playtimeMinutes ?? 0, bm = b.playtimeMinutes ?? 0
                if am != bm { return am > bm }
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

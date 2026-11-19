import Foundation

/// Search text plus the filtering and ordering rules for the library grid.
/// The rules are pure functions of the games and the set of installed bottles,
/// so they can be tested without any store.
@MainActor
final class SteamLibraryGridViewModel: ObservableObject {
    @Published var searchText: String = ""

    /// The game whose page was opened last, and the list it was opened from,
    /// so going back can scroll to it. Kept in memory only: a fresh launch
    /// starts at the top.
    private var openedGame: (appID: Int, filter: LibraryFilter, searchText: String, cardStyle: LibraryCardStyle)?

    /// Remembers the game whose page is opening and the list it came from.
    func gameOpened(_ appID: Int, filter: LibraryFilter, cardStyle: LibraryCardStyle) {
        openedGame = (appID, filter, searchText, cardStyle)
    }

    /// The game to scroll to when the grid comes back from a game page: the
    /// one opened, if the filter, search and card style are what they were
    /// and the game is still in `games`. Nil starts at the top. Answers once
    /// per return.
    func takeReturnScrollTarget(in games: [SteamLibraryGame], filter: LibraryFilter,
                                cardStyle: LibraryCardStyle) -> Int? {
        defer { openedGame = nil }
        guard let opened = openedGame,
              opened.filter == filter, opened.searchText == searchText, opened.cardStyle == cardStyle,
              games.contains(where: { $0.appID == opened.appID }) else { return nil }
        return opened.appID
    }

    func isInstalled(_ game: SteamLibraryGame, installedBottleIDs: Set<UUID>) -> Bool {
        guard let bottleID = game.installedBottleID else { return false }
        return installedBottleIDs.contains(bottleID)
    }

    /// The art for the cards just past `game` in `games`, to download before
    /// they scroll into view.
    func artToPrefetch(after game: SteamLibraryGame, in games: [SteamLibraryGame], style: LibraryCardStyle) -> [URL] {
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return [] }
        return games[(index + 1)...].prefix(GameArtCacheLimits.prefetchAhead).compactMap { $0.cardArt(for: style) }
    }

    func installedCount(in games: [SteamLibraryGame], installedBottleIDs: Set<UUID>) -> Int {
        games.filter { isInstalled($0, installedBottleIDs: installedBottleIDs) }.count
    }

    func filteredGames(
        from games: [SteamLibraryGame],
        installedBottleIDs: Set<UUID>,
        filter: LibraryFilter,
        sortOrder: LibrarySortOrder
    ) -> [SteamLibraryGame] {
        var base: [SteamLibraryGame]
        switch filter {
        case .all: base = games.filter { !$0.effectiveIsHidden }
        case .installed: base = games.filter { !$0.effectiveIsHidden && isInstalled($0, installedBottleIDs: installedBottleIDs) }
        case .hidden: base = games.filter(\.effectiveIsHidden)
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            base = base.filter { $0.name.lowercased().contains(q) || String($0.appID).contains(q) }
        }

        return base.sorted { a, b in
            // Favorites stay on top whatever the order.
            if a.effectiveIsFavorite != b.effectiveIsFavorite { return a.effectiveIsFavorite }
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

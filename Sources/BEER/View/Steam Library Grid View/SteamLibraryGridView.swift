import SwiftUI

struct SteamLibraryGridView: View {
    var onSelectGame: (SteamLibraryGame) -> Void
    /// When true, show only installed games (the "Installed" sidebar tab).
    var installedOnly: Bool = false

    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var bottles: BottleStore
    @StateObject private var model = SteamLibraryGridViewModel()

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 18, alignment: .top)
    ]

    var body: some View {
        let installedIDs = Set(bottles.bottles.map(\.id))
        let games = model.filteredGames(from: library.games, installedBottleIDs: installedIDs, installedOnly: installedOnly)

        VStack(spacing: 0) {
            LibraryToolbarView(
                searchText: $model.searchText,
                installedOnly: installedOnly,
                summary: installedOnly
                    ? "\(games.count) installed"
                    : "\(model.installedCount(in: library.games, installedBottleIDs: installedIDs)) installed · \(library.games.count) games"
            )
            Divider()
            if library.isFetchingLibrary && library.games.isEmpty {
                ProgressView("Fetching your library…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if library.games.isEmpty {
                LibraryEmptyStateView(icon: "tray", title: "No games yet",
                                      message: "Click Refresh to fetch your Steam library.")
            } else if games.isEmpty {
                if installedOnly {
                    LibraryEmptyStateView(icon: "internaldrive", title: "No games installed yet",
                                          message: "Open a game in your Library and click Install — it'll show up here.")
                } else {
                    LibraryEmptyStateView(icon: "magnifyingglass", title: "No matches",
                                          message: "No games match “\(model.searchText)”.")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(games) { game in
                            GameCardView(
                                game: game,
                                isInstalled: model.isInstalled(game, installedBottleIDs: installedIDs),
                                action: { onSelectGame(game) }
                            )
                        }
                    }
                    .padding(22)
                }
            }
        }
    }
}

import SwiftUI

struct LibraryPane: View {
    @Binding var selectedGameAppID: Int?
    @Binding var filter: LibraryFilter
    @Environment(SteamLibraryStore.self) private var library
    /// Owned here, not by the grid, so the search and the game to scroll back
    /// to outlive the grid while a game page is showing.
    @State private var gridModel = SteamLibraryGridViewModel()
    @AppStorage(AppearancePreferences.cardStyleKey) private var cardStyle = AppearanceDefaults.cardStyle

    var body: some View {
        Group {
            if let appID = selectedGameAppID,
               let game = library.games.first(where: { $0.appID == appID }) {
                GameDetailView(
                    game: game,
                    onBack: { selectedGameAppID = nil }
                )
            } else {
                SteamLibraryGridView(
                    model: gridModel,
                    onSelectGame: { selectedGameAppID = $0.appID },
                    filter: $filter
                )
            }
        }
        // Here rather than on a card's tap, so a game opened from a shortcut
        // link is the one scrolled to as well.
        .onChange(of: selectedGameAppID) { _, appID in
            if let appID { gridModel.gameOpened(appID, filter: filter, cardStyle: cardStyle) }
        }
    }
}

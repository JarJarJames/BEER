import SwiftUI

struct LibraryPane: View {
    @Binding var selectedGameAppID: Int?
    @Binding var filter: LibraryFilter
    @EnvironmentObject private var library: SteamLibraryStore

    var body: some View {
        if let appID = selectedGameAppID,
           let game = library.games.first(where: { $0.appID == appID }) {
            GameDetailView(
                game: game,
                onBack: { selectedGameAppID = nil }
            )
        } else {
            SteamLibraryGridView(
                onSelectGame: { selectedGameAppID = $0.appID },
                filter: $filter
            )
        }
    }
}

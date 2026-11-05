import SwiftUI

/// Favorite and Hide for one game, for a card's right-click menu and the game
/// page's menu.
struct GameOrganizeMenuItems: View {
    let game: SteamLibraryGame
    @EnvironmentObject private var library: SteamLibraryStore

    var body: some View {
        Button {
            library.setFavorite(!game.effectiveIsFavorite, appID: game.appID)
        } label: {
            Label(game.effectiveIsFavorite ? GameOrganizeStrings.removeFavorite : GameOrganizeStrings.addFavorite,
                  systemImage: game.effectiveIsFavorite ? "star.slash" : "star")
        }
        Button {
            library.setHidden(!game.effectiveIsHidden, appID: game.appID)
        } label: {
            Label(game.effectiveIsHidden ? GameOrganizeStrings.unhide : GameOrganizeStrings.hide,
                  systemImage: game.effectiveIsHidden ? "eye" : "eye.slash")
        }
    }
}

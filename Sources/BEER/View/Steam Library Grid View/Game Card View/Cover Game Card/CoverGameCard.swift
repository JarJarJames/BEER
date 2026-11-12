import SwiftUI

/// Steam's portrait cover with the name under it.
struct CoverGameCard: View {
    let game: SteamLibraryGame
    let caption: String?
    /// False leaves the art alone, with no name bar under it.
    let showsName: Bool
    let badge: InstalledBadge

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(LibraryGridLayout.coverArtAspectRatio, contentMode: .fit)
                .overlay { GameCoverArt(game: game) }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    badge
                        .padding(LibraryGridLayout.badgeInset)
                        .padding(.leading, game.effectiveIsFavorite ? LibraryGridLayout.favoriteClearance : 0)
                }
                .overlay(alignment: .topLeading) {
                    if game.effectiveIsFavorite { FavoriteMark().padding(LibraryGridLayout.badgeInset) }
                }
            if showsName {
                GameCardCaption(name: game.name, caption: caption)
                    .padding(LibraryGridLayout.captionPadding)
            }
        }
    }
}

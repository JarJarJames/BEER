import SwiftUI

/// Steam's wide header art with the name under it: the original card.
struct WideGameCard: View {
    let game: SteamLibraryGame
    let caption: String?
    /// False leaves the art alone, with no name bar under it.
    let showsName: Bool
    let badge: InstalledBadge?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(LibraryGridLayout.wideArtAspectRatio, contentMode: .fit)
                .overlay { GameArtImage(url: game.headerImage) }
                .clipped()
                .overlay(alignment: .topTrailing) { badge?.padding(LibraryGridLayout.badgeInset) }
            if showsName {
                GameCardCaption(name: game.name, caption: caption)
                    .padding(LibraryGridLayout.captionPadding)
            }
        }
    }
}

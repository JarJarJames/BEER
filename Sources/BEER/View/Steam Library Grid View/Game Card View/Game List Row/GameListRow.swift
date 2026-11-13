import SwiftUI

/// One row of the list style: icon, name and caption, and the badge.
struct GameListRow: View {
    let game: SteamLibraryGame
    let caption: String?
    let badge: InstalledBadge
    let iconSize: CGFloat

    var body: some View {
        HStack(spacing: LibraryGridLayout.listRowSpacing) {
            // The name is right beside it, so the placeholder doesn't repeat it.
            GameArtImage(url: game.listIcon, title: nil)
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: LibraryGridLayout.listIconCornerRadius))

            GameCardCaption(name: game.name, caption: caption)
            if game.effectiveIsFavorite { FavoriteMark() }
            // A row has the room: the name truncates, never the badge.
            badge.fixedSize()
        }
        .padding(.horizontal, LibraryGridLayout.listRowHorizontalPadding)
        .padding(.vertical, LibraryGridLayout.listRowVerticalPadding)
    }
}

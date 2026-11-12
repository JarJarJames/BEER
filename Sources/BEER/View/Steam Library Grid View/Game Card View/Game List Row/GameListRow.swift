import SwiftUI

/// One row of the list style: icon, name and caption, and the badge.
struct GameListRow: View {
    let game: SteamLibraryGame
    let caption: String?
    let badge: InstalledBadge
    let iconSize: CGFloat

    var body: some View {
        HStack(spacing: LibraryGridLayout.listRowSpacing) {
            AsyncImage(url: game.listIcon) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "gamecontroller").foregroundStyle(.secondary)
                }
            }
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

import SwiftUI

/// What a card shows until its art arrives, or when it has none: the game's
/// name, so a fast scroll past unloaded cards can still be read. Without a
/// name (a list row, which shows it beside the icon) a controller symbol.
struct GameArtPlaceholder: View {
    let title: String?

    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(LibraryGridLayout.placeholderOpacity))
            .overlay {
                if let title {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(LibraryGridLayout.placeholderTitleLines)
                        .minimumScaleFactor(LibraryGridLayout.placeholderMinimumScale)
                        .padding(LibraryGridLayout.placeholderPadding)
                } else {
                    Image(systemName: "gamecontroller").foregroundStyle(.secondary)
                }
            }
    }
}

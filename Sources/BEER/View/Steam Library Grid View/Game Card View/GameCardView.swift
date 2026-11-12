import SwiftUI

/// One game in the library, in the chosen style. Owns the click and the hover
/// highlight; the style views only lay the game out.
struct GameCardView: View {
    let game: SteamLibraryGame
    let isInstalled: Bool
    /// Installed on a drive that isn't connected.
    var isDriveMissing: Bool = false
    let style: LibraryCardStyle
    /// The size slider's width, which sets a list row's icon.
    let cardWidth: Double
    let caption: String?
    let showsName: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            card
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: LibraryGridLayout.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: LibraryGridLayout.cornerRadius)
                        .stroke(isHovering ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isHovering ? 2 : 1)
                )
                // A full-width row growing would push past the window's edge.
                .scaleEffect(isHovering && style != .list ? LibraryGridLayout.hoverScale : 1.0)
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Art-only cards still name the game on hover and to VoiceOver.
        .help(game.name)
        .accessibilityLabel(game.name)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder private var card: some View {
        let badge = isInstalled
            ? InstalledBadge(isDriveMissing: isDriveMissing, hasUpdate: game.effectiveUpdateAvailable)
            : nil
        switch style {
        case .wide:
            WideGameCard(game: game, caption: caption, showsName: showsName, badge: badge)
        case .cover:
            CoverGameCard(game: game, caption: caption, showsName: showsName, badge: badge)
        case .list:
            GameListRow(game: game, caption: caption, badge: badge,
                        iconSize: LibraryGridLayout.listIconSize(chosen: cardWidth))
        }
    }
}

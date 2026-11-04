import SwiftUI

/// The game's logo art, or its name when it has none.
struct SteamLibraryLogo: View {
    let game: SteamLibraryGame
    /// Scales the name's font; the logo art fills whatever frame it's given.
    var scale: CGFloat = 1

    var body: some View {
        AsyncImage(url: game.libraryLogoImage) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(game.name)
            } else {
                Text(game.name)
                    .font(.system(size: GameBannerLayout.titleFontSize * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
            }
        }
        .shadow(color: .black.opacity(0.65), radius: 8, y: 2)
    }
}

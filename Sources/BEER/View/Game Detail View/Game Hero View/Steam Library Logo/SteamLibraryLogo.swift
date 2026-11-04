import SwiftUI

struct SteamLibraryLogo: View {
    let game: SteamLibraryGame
    /// False shows the name as text even when Steam has logo art.
    var usesLogoArt = true
    /// Scales the name's font; the logo art fills whatever frame it's given.
    var scale: CGFloat = 1

    var body: some View {
        Group {
            if usesLogoArt {
                AsyncImage(url: game.libraryLogoImage) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFit()
                            .accessibilityLabel(game.name)
                    } else {
                        title
                    }
                }
            } else {
                title
            }
        }
        .shadow(color: .black.opacity(0.65), radius: 8, y: 2)
    }

    private var title: some View {
        Text(game.name)
            .font(.system(size: GameBannerLayout.titleFontSize * scale, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
    }
}

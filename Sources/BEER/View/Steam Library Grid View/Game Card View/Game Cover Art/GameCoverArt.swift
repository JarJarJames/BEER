import SwiftUI

/// A cover card's art. Steam's portrait cover fills the card; a game without
/// one (older Steam games, non-Steam games) shows its wide art whole, over a
/// blurred copy of itself, rather than cropped down to the middle.
struct GameCoverArt: View {
    let game: SteamLibraryGame

    var body: some View {
        if let cover = game.portraitCover {
            AsyncImage(url: cover) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .empty:
                    Rectangle().fill(Color.secondary.opacity(0.15))
                default:
                    fittedArt
                }
            }
        } else {
            fittedArt
        }
    }

    private var fittedArt: some View {
        AsyncImage(url: game.headerImage) { phase in
            if case .success(let image) = phase {
                ZStack {
                    image.resizable().aspectRatio(contentMode: .fill)
                        .blur(radius: LibraryGridLayout.fittedArtBlur)
                    image.resizable().aspectRatio(contentMode: .fit)
                }
            } else {
                Rectangle().fill(Color.secondary.opacity(0.15))
                    .overlay(Image(systemName: "gamecontroller").foregroundStyle(.secondary))
            }
        }
    }
}

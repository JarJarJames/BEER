import SwiftUI

/// A cover card's art. Steam's portrait cover fills the card; a game without
/// one (older Steam games, non-Steam games) shows its wide art whole, over a
/// blurred copy of itself, rather than cropped down to the middle.
struct GameCoverArt: View {
    let game: SteamLibraryGame

    var body: some View {
        if let cover = game.portraitCover {
            GameArtImage(url: cover) {
                GameArtPlaceholder(title: game.name)
            } failure: {
                fittedArt
            }
        } else {
            fittedArt
        }
    }

    /// The blurred copy is decoded tiny and blurred once, then stretched:
    /// it looks the same as blurring the full image, for a sliver of the memory.
    private var fittedArt: some View {
        ZStack {
            GameArtImage(url: game.headerImage, fit: .backdrop) { Color.clear } failure: { Color.clear }
            GameArtImage(url: game.headerImage, fit: .fit, title: game.name)
        }
    }
}

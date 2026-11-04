import SwiftUI

/// The game's art, blurred and dimmed, behind its whole page.
struct GamePageBackdrop: View {
    let game: SteamLibraryGame

    var body: some View {
        SteamHeroArtwork(game: game)
            .blur(radius: GameBannerLayout.backdropBlur)
            .scaleEffect(GameBannerLayout.backdropScale)
            .opacity(GameBannerLayout.backdropOpacity)
            .clipped()
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

import SwiftUI

struct GameHeroView: View {
    @ObservedObject var model: GameDetailViewModel

    private var game: SteamLibraryGame { model.game }

    @AppStorage(AppearancePreferences.bannerHeightKey) private var bannerHeight = GameBannerLayout.defaultHeightRatio
    @AppStorage(AppearancePreferences.titleStyleKey) private var titleStyle: GameTitleStyle = .logo
    @AppStorage(AppearancePreferences.titleScaleKey) private var titleScale = GameBannerLayout.defaultTitleScale
    @AppStorage(AppearancePreferences.layoutKey) private var layout: GamePageLayout = .overlay
    @AppStorage(AppearancePreferences.shownStatsKey) private var shownStats = GamePageStat.encode(GamePageStat.defaultShown)
    @AppStorage(AppearancePreferences.playtimeFormatKey) private var playtimeFormat: PlaytimeFormat = .decimalHours
    @AppStorage(AppearancePreferences.lastPlayedFormatKey) private var lastPlayedFormat: LastPlayedFormat = .date

    private var stats: [GameStat] {
        GamePageStat.stats(GamePageStat.decode(shownStats), for: game, installedBytes: model.installedBytes,
                           playtime: playtimeFormat, lastPlayed: lastPlayedFormat)
    }

    var body: some View {
        switch layout {
        case .overlay: overlayHero
        case .steam: steamHero
        }
    }

    /// The original look: everything on the art, in a rounded card.
    private var overlayHero: some View {
        banner { details }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
    }

    /// Like Steam's game pages: the art runs edge to edge and fades into the
    /// page, and Play and the stats sit on a see-through strip across its
    /// bottom, with the art still showing behind them. No card, no border.
    private var steamHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            banner { logo.padding(.horizontal, GameBannerLayout.pageInset).padding(.vertical, 26) }
            GameStatBar(model: model, stats: stats)
        }
        .background(alignment: .top) {
            SteamHeroArtwork(game: game)
                .overlay {
                    // Just enough behind the logo to keep a light one readable.
                    LinearGradient(colors: [.black.opacity(0.3), .clear], startPoint: .leading, endPoint: .center)
                }
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: GameBannerLayout.fadeStart),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    /// The banner's height from the slider, or taller if `content` needs it,
    /// with `content` at its bottom left. The art is never a sibling here:
    /// filling a shape other than its own, it's bigger than the banner, and in
    /// a stack it would widen the banner past the window.
    private func banner(@ViewBuilder _ content: () -> some View) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(1 / CGFloat(bannerHeight), contentMode: .fit)
            content()
        }
        .background { if layout == .overlay { artwork } }
    }

    private var artwork: some View {
        ZStack {
            SteamHeroArtwork(game: game)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.28),
                    .init(color: .black.opacity(0.34), location: 0.55),
                    .init(color: .black.opacity(0.88), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [.black.opacity(0.38), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var logo: some View {
        SteamLibraryLogo(game: game, usesLogoArt: titleStyle == .logo, scale: CGFloat(titleScale))
            .frame(maxWidth: GameBannerLayout.logoMaxWidth * CGFloat(titleScale),
                   maxHeight: GameBannerLayout.logoMaxHeight * CGFloat(titleScale), alignment: .leading)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            logo
            overlayStats
            GameActionRow(model: model)
        }
        .padding(26)
        .environment(\.colorScheme, .dark)
    }

    private var overlayStats: some View {
        HStack(spacing: 12) {
            ForEach(stats) { Label($0.inline, systemImage: $0.systemImage) }
            if model.installedBottle != nil {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Not installed", systemImage: "circle.dashed")
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
        .font(.callout)
        .foregroundStyle(.white.opacity(0.78))
    }
}

import SwiftUI

struct GameHeroView: View {
    @ObservedObject var model: GameDetailViewModel

    private var game: SteamLibraryGame { model.game }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
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

            VStack(alignment: .leading, spacing: 10) {
                SteamLibraryLogo(game: game)
                    .frame(maxWidth: 420, maxHeight: 150, alignment: .leading)

                HStack(spacing: 12) {
                    Label("appID \(game.appID)", systemImage: "number")
                    if let playtime = game.playtimeDisplay {
                        Label(playtime, systemImage: "clock")
                    }
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

                GameActionRow(model: model)
            }
            .padding(26)
            .environment(\.colorScheme, .dark)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1920.0 / 620.0, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
    }
}

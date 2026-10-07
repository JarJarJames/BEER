import SwiftUI

struct GameCardView: View {
    let game: SteamLibraryGame
    let isInstalled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: game.headerImage) { phase in
                        switch phase {
                        case .empty:
                            Rectangle().fill(Color.secondary.opacity(0.15))
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            Rectangle().fill(Color.secondary.opacity(0.15))
                                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                        @unknown default:
                            Rectangle().fill(Color.secondary.opacity(0.15))
                        }
                    }
                    .frame(height: 108)
                    .clipped()

                    if isInstalled {
                        Text("INSTALLED")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(game.name)
                        .font(.callout.bold())
                        .lineLimit(1)
                    Text(game.effectiveIsNonSteam ? "Non-Steam" : "appID \(game.appID)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovering ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isHovering ? 2 : 1)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

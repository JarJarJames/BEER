import SwiftUI

struct SteamLibraryLogo: View {
    let game: SteamLibraryGame

    var body: some View {
        AsyncImage(url: game.libraryLogoImage) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(game.name)
            } else {
                Text(game.name)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        .shadow(color: .black.opacity(0.65), radius: 8, y: 2)
    }
}

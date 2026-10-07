import SwiftUI

struct SteamHeroArtwork: View {
    let game: SteamLibraryGame

    var body: some View {
        if game.libraryHeroImage == nil && game.headerImage == nil {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .overlay(Image(systemName: "gamecontroller").font(.largeTitle).foregroundStyle(.secondary))
        } else {
            artwork
        }
    }

    private var artwork: some View {
        AsyncImage(url: game.libraryHeroImage ?? game.headerImage) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay { ProgressView().controlSize(.small) }
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                fallbackArtwork
            @unknown default:
                fallbackArtwork
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    var fallbackArtwork: some View {
        AsyncImage(url: game.headerImage) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 2)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
    }
}

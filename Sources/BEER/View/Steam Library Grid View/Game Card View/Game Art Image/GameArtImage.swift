import SwiftUI

/// Art that fills whatever frame it's given, with a grey placeholder while it
/// loads or when it can't.
struct GameArtImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure:
                Rectangle().fill(Color.secondary.opacity(0.15))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            default:
                Rectangle().fill(Color.secondary.opacity(0.15))
            }
        }
    }
}

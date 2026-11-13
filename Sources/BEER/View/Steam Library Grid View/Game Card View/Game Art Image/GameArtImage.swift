import SwiftUI

/// Art that fills (or sits inside) whatever frame it's given, decoded at that
/// frame's size through `GameArtStore`. Shows `placeholder` while it loads and
/// `failure` when there's no art.
///
/// The image is held only while the card is on screen: the lazy grid may keep
/// a card's state after it scrolls away, so it lets go on disappearing.
struct GameArtImage<Placeholder: View, Failure: View>: View {
    let url: URL?
    let fit: GameArtRequest.Fit
    let placeholder: Placeholder
    let failure: Failure

    @Environment(\.displayScale) private var displayScale
    @State private var size: CGSize = .zero
    @State private var phase: GameArtPhase = .loading

    init(
        url: URL?, fit: GameArtRequest.Fit = .fill,
        @ViewBuilder placeholder: () -> Placeholder, @ViewBuilder failure: () -> Failure
    ) {
        self.url = url
        self.fit = fit
        self.placeholder = placeholder()
        self.failure = failure()
    }

    private var request: GameArtRequest? {
        GameArtRequest(url: url, points: size, scale: displayScale, fit: fit)
    }

    var body: some View {
        Color.clear
            .overlay { content }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .task(id: request) { await load() }
            .onDisappear { phase = .loading }
    }

    @ViewBuilder private var content: some View {
        if let image = phase.image {
            Image(decorative: image, scale: displayScale)
                .resizable()
                .aspectRatio(contentMode: fit == .fit ? .fit : .fill)
        } else if url == nil || phase.isFailed {
            failure
        } else {
            placeholder
        }
    }

    private func load() async {
        guard let request else { return }
        // A new size keeps showing the old image until the new one is ready.
        let image = await GameArtStore.shared.image(for: request)
        guard !Task.isCancelled else { return }
        phase = GameArtPhase(image)
    }
}

extension GameArtImage where Placeholder == GameArtPlaceholder, Failure == GameArtPlaceholder {
    /// The placeholder, naming the game, both while loading and when there's no art.
    init(url: URL?, fit: GameArtRequest.Fit = .fill, title: String?) {
        self.init(url: url, fit: fit) {
            GameArtPlaceholder(title: title)
        } failure: {
            GameArtPlaceholder(title: title)
        }
    }
}

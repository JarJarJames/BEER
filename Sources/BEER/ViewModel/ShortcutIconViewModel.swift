import CoreGraphics
import Foundation

/// State behind the shortcut icon sheet: the cover to crop, whether Steam's
/// icon is big enough to offer, and the player's pick.
@MainActor
final class ShortcutIconViewModel: ObservableObject {
    enum SteamIcon: Equatable {
        case checking
        /// Steam lists none, or none at 256×256 or larger.
        case unavailable
        case available(CGImage)
    }

    let game: SteamLibraryGame
    private let account: SteamCloudAccount?
    private let client: CloudSyncClient
    private let fetch: @Sendable (URL) async throws -> Data
    /// Keeps the icon address Steam gave, so it isn't asked for again.
    private let rememberClientIcon: (URL) -> Void

    @Published private(set) var cover: CGImage?
    @Published private(set) var steamIcon: SteamIcon
    @Published var choice: ShortcutIconChoice
    @Published private(set) var error: String?

    init(
        game: SteamLibraryGame,
        account: SteamCloudAccount?,
        client: CloudSyncClient = CloudSyncClient(),
        fetch: @escaping @Sendable (URL) async throws -> Data = GameShortcutStore.download,
        rememberClientIcon: @escaping (URL) -> Void
    ) {
        self.game = game
        self.account = account
        self.client = client
        self.fetch = fetch
        self.rememberClientIcon = rememberClientIcon
        choice = game.shortcutIcon ?? .default
        steamIcon = game.effectiveIsNonSteam ? .unavailable : .checking
    }

    /// The crop being edited, or the centred one while Steam's icon is picked.
    var crop: CoverCrop {
        get { if case .cover(let c) = choice { c } else { .centered } }
        set { choice = .cover(cover.map { newValue.clamped(to: CGSize(width: $0.width, height: $0.height)) } ?? newValue) }
    }

    /// What the shortcut will show with the current pick.
    var previewImage: CGImage? {
        switch choice {
        case .steamIcon:
            if case .available(let image) = steamIcon { image } else { nil }
        case .cover(let crop):
            cover.flatMap { ShortcutIconImage.crop($0, to: crop) }
        }
    }

    func load() async {
        async let coverLoad: Void = loadCover()
        async let iconLoad: Void = loadSteamIcon()
        _ = await (coverLoad, iconLoad)
        // A Steam icon picked earlier that is no longer offered falls back to the cover.
        if choice == .steamIcon, steamIcon == .unavailable { choice = .default }
    }

    private func loadCover() async {
        guard let url = game.shortcutCoverImage else {
            error = GameShortcutStrings.noArtwork
            return
        }
        do {
            cover = ShortcutIconImage.image(from: try await fetch(url))
            if cover == nil { error = GameShortcutStrings.artworkUnreadable }
        } catch {
            self.error = GameShortcutStrings.artworkUnreadable
        }
    }

    private func loadSteamIcon() async {
        guard !game.effectiveIsNonSteam else { return }
        var iconURL = game.clientIconURL.flatMap(URL.init(string:))
        if iconURL == nil, let account {
            iconURL = try? await client.clientIcon(
                appID: game.appID, account: account.accountName, refreshToken: account.refreshToken
            )
            if let iconURL { rememberClientIcon(iconURL) }
        }
        guard let iconURL, let data = try? await fetch(iconURL),
              let image = ShortcutIconImage.steamIcon(from: data) else {
            steamIcon = .unavailable
            return
        }
        steamIcon = .available(image)
    }
}

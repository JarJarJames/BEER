import Foundation

/// Art the player picked for a game, copied under
/// `AppPaths.customArtDirectory`. Each piece is used in place of Steam's.
struct CustomGameArt: Codable, Hashable {
    var coverPath: String?
    var bannerPath: String?
    var logoPath: String?

    var isEmpty: Bool { coverPath == nil && bannerPath == nil && logoPath == nil }

    var paths: [String] { [coverPath, bannerPath, logoPath].compactMap { $0 } }

    func path(for slot: GameArtSlot) -> String? {
        switch slot {
        case .cover: coverPath
        case .banner: bannerPath
        case .logo: logoPath
        }
    }

    func url(for slot: GameArtSlot) -> URL? {
        path(for: slot).map { URL(fileURLWithPath: $0) }
    }

    mutating func setPath(_ path: String?, for slot: GameArtSlot) {
        switch slot {
        case .cover: coverPath = path
        case .banner: bannerPath = path
        case .logo: logoPath = path
        }
    }
}

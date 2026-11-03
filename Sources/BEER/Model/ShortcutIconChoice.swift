/// What a game's shortcuts show as their icon.
enum ShortcutIconChoice: Codable, Hashable {
    /// Steam's own Windows icon, offered only when it has a 256×256 image.
    case steamIcon
    /// A square cut from the game's cover.
    case cover(CoverCrop)

    static let `default` = ShortcutIconChoice.cover(.centered)
}

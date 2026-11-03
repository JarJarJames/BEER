import Foundation

/// Sizes for the shortcut icon sheet.
enum ShortcutIconSheetLayout {
    static let sheetWidth: CGFloat = 520
    /// The cover is shown this wide; its height follows its shape.
    static let coverWidth: CGFloat = 240
    /// Dock size, so the preview shows how the icon reads where it's used.
    static let previewSide: CGFloat = 128
    static let previewCornerRadius: CGFloat = 22
    static let cropBorderWidth: CGFloat = 2
    static let dimOpacity: Double = 0.55
    static let buttonWidth: CGFloat = 120
}

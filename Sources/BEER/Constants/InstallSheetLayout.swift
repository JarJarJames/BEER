import Foundation

/// Sizes for the sheet shown before a game downloads.
enum InstallSheetLayout {
    static let sheetWidth: CGFloat = 520
    static let artworkWidth: CGFloat = 150
    /// Steam's header.jpg is 460×215.
    static let artworkHeight: CGFloat = 70
    static let buttonWidth: CGFloat = 160
    /// The DLC list scrolls past this many rows, up to this height.
    static let dlcRowsWithoutScrolling = 8
    static let dlcListMaxHeight: CGFloat = 200
}

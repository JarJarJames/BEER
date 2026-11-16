import Foundation

/// Sizes for the launch status on the game page, matching the Play button it
/// stands in for.
enum LaunchStatusLayout {
    static let minWidth: CGFloat = 180
    static let minHeight: CGFloat = 36
    static let horizontalPadding: CGFloat = 12
    static let cornerRadius: CGFloat = 8
    static let spacing: CGFloat = 8
    static let backgroundOpacity: Double = 0.18
    /// How wide a hint or error under the status may grow before wrapping.
    static let noteMaxWidth: CGFloat = 420
    static let noteLineLimit = 3
}

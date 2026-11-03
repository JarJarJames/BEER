import Foundation

/// Sizes for the main window's sidebar.
enum MainShellLayout {
    /// The sidebar's width bounds, set outright. Left to its content, the
    /// sidebar's minimum followed the account bar's text, and Steam changing
    /// that text mid-layout (a game starting or ending, the nickname arriving)
    /// sent the window into an endless constraint pass that AppKit aborts.
    static let sidebarMinWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 230
    static let sidebarMaxWidth: CGFloat = 320
}

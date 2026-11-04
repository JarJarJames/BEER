import Foundation

/// Sizes for the main window and its top bar.
enum MainShellLayout {
    /// The window's smallest content size, set outright: left to its
    /// content, a change on the game page (a game starting, a log line, a
    /// row appearing) gave the window a new minimum mid-layout, and AppKit
    /// aborted the pass loop that followed.
    static let detailMinWidth: CGFloat = 600
    static let detailMinHeight: CGFloat = 400

    /// The account menu's width in the top bar, set outright for the same
    /// reason: Steam changes the status under the name mid-layout ("In-Game ·
    /// <game>" → "Online" when a game ends), and a toolbar item sized to that
    /// text sent the window into an endless constraint pass. Long names and
    /// statuses truncate instead.
    static let accountMenuWidth: CGFloat = 190
    static let avatarSize: CGFloat = 24
    static let accountPanelWidth: CGFloat = 300
    /// The Downloads button's width while downloading, fixed for the same
    /// reason: the percent changes many times a second.
    static let downloadsButtonWidth: CGFloat = 64
    static let toolbarIconSize: CGFloat = 16
    static let toolbarButtonPadding: CGFloat = 8
    static let downloadsPopoverSize = CGSize(width: 440, height: 480)
}

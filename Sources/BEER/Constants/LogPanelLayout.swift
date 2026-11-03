import Foundation

/// Heights of the log panels on the game page (the Wine log and the
/// DepotDownloader output). Fixed rather than following their lines: a panel
/// sized by its content is a scroll view inside the page's scroll view whose
/// height changes as lines arrive and as its lazy rows measure themselves,
/// and opening the Wine log while a game started sent the window into a
/// layout loop that AppKit aborts.
enum LogPanelLayout {
    static let wineLogHeight: CGFloat = 200
    static let downloadOutputHeight: CGFloat = 160
    /// How close to the end of the log counts as at the end, so a scroll
    /// that stops a few points short still follows new lines.
    static let atEndTolerance: CGFloat = 12
}

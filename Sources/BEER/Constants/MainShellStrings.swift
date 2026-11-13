import Foundation

/// User-facing text for the main window's top bar.
enum MainShellStrings {
    static let appName = "BEER"
    /// Shown in place of a version number when BEER runs from `swift run`.
    static let devVersion = "dev"

    /// "BEER 0.6.2", or "BEER dev" under `swift run`.
    static func windowTitle(version: String = AppVersion.label()) -> String {
        "\(appName) \(version)"
    }
}

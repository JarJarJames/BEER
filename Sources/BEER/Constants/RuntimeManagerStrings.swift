import Foundation

/// User-facing text in the Runtime Manager.
enum RuntimeManagerStrings {
    static let installedTitle = "Installed runtimes"
    static let installedDescription = "Wine and GPTK builds currently available to installed games."
    static let installedBEERGroup = "BEER runtimes"
    static let installedOtherGroup = "Other runtimes"

    static let beerTitle = "BEER runtimes"
    static let beerDescription = "BEER's own Game Porting Toolkit builds: CrossOver's open-source Wine with Apple's newest D3DMetal."
    static let gptkTitle = "Game Porting Toolkit"
    static let gptkDescription = "Apple-focused Wine builds with D3DMetal for the best DirectX performance on Apple silicon."

    static let recommended = "Recommended for this Mac"
    static let installed = "Installed"
    static let download = "Download"
    static func needsMacOS(_ version: Int) -> String { "Needs macOS \(version)" }
}

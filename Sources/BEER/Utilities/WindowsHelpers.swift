import Foundation

/// BEER's own small Windows programs (Tools/WindowsHelpers), which run inside
/// a bottle beside a game: bundled in a shipped .app, or where
/// `scripts/build_windows_helpers.sh` installs them for a `swift run` build.
enum WindowsHelpers {
    /// Starts a launcher with `launchHook` in it; reads `launchConfig`.
    static let launcher = "beer_launch.exe"
    static let launchHook = "beer_launch_hook.dll"
    static let launchConfig = "beer_launch.txt"
    /// Starts a script extender in the game; reads `scriptExtenderConfig`.
    static let scriptExtenderStarter = "beer_xse_start.dll"
    static let scriptExtenderConfig = "beer_xse_start.txt"

    /// The folder holding them; nil when they haven't been built.
    static var directory: URL? {
        [Bundle.main.resourceURL, AppPaths.windowsHelpersDirectory].compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent(launcher).path)
        }
    }
}

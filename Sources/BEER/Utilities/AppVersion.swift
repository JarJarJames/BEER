import Foundation

/// The version BEER shows next to its name in the window title.
enum AppVersion {
    /// `CFBundleShortVersionString` from the app's Info.plist, which
    /// `scripts/build_app.sh` writes. `swift run` has no Info.plist, so a
    /// missing or blank version reads as "dev".
    static func label(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let version = (info?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let version, !version.isEmpty else { return MainShellStrings.devVersion }
        return version
    }
}

import Foundation

/// Sizes for the Settings window's tabs. Fixed, so switching tabs resizes the
/// window to a known size rather than following the content.
enum SettingsLayout {
    static let appearanceSize = CGSize(width: 480, height: 640)
    static let runtimesSize = CGSize(width: 780, height: 640)
}

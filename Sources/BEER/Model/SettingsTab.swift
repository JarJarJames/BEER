import Foundation

/// The Settings window's tabs.
enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance
    /// Installing Wine and GPTK builds and graphics translators. Set up once
    /// and rarely touched, so it lives here rather than in the main window.
    case runtimes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appearance: "Appearance"
        case .runtimes: "Runtimes"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: "paintbrush"
        case .runtimes: "shippingbox"
        }
    }
}

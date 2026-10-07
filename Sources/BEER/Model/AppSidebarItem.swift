import SwiftUI

enum AppSidebarItem: String, Hashable, CaseIterable, Identifiable {
    case library
    case installed
    case downloads
    case runtimes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .library: "Library"
        case .installed: "Installed"
        case .downloads: "Downloads"
        case .runtimes: "Runtime Manager"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "rectangle.stack.fill"
        case .installed: "internaldrive.fill"
        case .downloads: "arrow.down.circle"
        case .runtimes: "shippingbox.fill"
        }
    }
}

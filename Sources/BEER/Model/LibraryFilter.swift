import Foundation

/// Which games the library shows, picked in the window's top bar.
enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case installed

    static let pickerLabel = "Show"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All Games"
        case .installed: "Installed"
        }
    }
}

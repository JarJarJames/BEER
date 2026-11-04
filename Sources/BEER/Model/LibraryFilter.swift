import Foundation

/// Which games the library shows, picked in the window's top bar.
enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case installed
    /// Games the player hid. Offered only while there are some.
    case hidden

    static let pickerLabel = "Show"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All Games"
        case .installed: "Installed"
        case .hidden: "Hidden"
        }
    }

    var searchPrompt: String {
        switch self {
        case .all: "Search library"
        case .installed: "Search installed"
        case .hidden: "Search hidden"
        }
    }
}

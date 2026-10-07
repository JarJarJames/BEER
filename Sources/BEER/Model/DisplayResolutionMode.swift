import Foundation

enum DisplayResolutionMode: String, Codable, CaseIterable, Identifiable {
    case standard
    case highResolution

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .highResolution: "High Resolution"
        }
    }
}

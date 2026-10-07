import Foundation

enum RuntimeKind: String, Codable, CaseIterable, Identifiable {
    case systemWine
    case crossOver
    case whisky
    case gamePortingToolkit
    case gameNativeWine
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .systemWine: "System Wine"
        case .crossOver: "CrossOver"
        case .whisky: "Whisky Wine"
        case .gamePortingToolkit: "Game Porting Toolkit"
        case .gameNativeWine: "GameNative Wine"
        case .custom: "Custom Wine"
        }
    }
}

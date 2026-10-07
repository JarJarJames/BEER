import Foundation

enum GraphicsBackend: String, Codable, CaseIterable, Identifiable {
    case automatic
    case d3dMetal
    case dxmt
    case dxvk
    case wineD3D

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .d3dMetal: "D3DMetal"
        case .dxmt: "DXMT"
        case .dxvk: "DXVK"
        case .wineD3D: "WineD3D"
        }
    }
}

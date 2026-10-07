import Foundation

enum GraphicsTranslator: String, CaseIterable, Identifiable {
    case dxvk
    case dxmt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dxvk: "DXVK (D3D→Vulkan)"
        case .dxmt: "DXMT (D3D→Metal)"
        }
    }

    /// GitHub repo we pull release archives from.
    var repo: String {
        switch self {
        case .dxvk: "Gcenx/DXVK-macOS"
        case .dxmt: "3Shain/dxmt"
        }
    }

    /// Pick the right asset for this translator. DXVK has many variants — we
    /// need the FULL `dxvk-macOS-async-<ver>.tar.gz` (ships its own dxgi.dll,
    /// x64/x32 layout), NOT the `-builtin`/`-repack`/`-CrossOver` strips that
    /// omit dxgi. DXMT ships a single complete `-builtin` archive.
    func matchesAsset(_ name: String) -> Bool {
        let l = name.lowercased()
        guard l.hasSuffix(".tar.gz") else { return false }
        switch self {
        case .dxvk:
            return l.hasPrefix("dxvk-macos-async")
                && !l.contains("builtin") && !l.contains("repack") && !l.contains("crossover")
        case .dxmt:
            return l.contains("builtin")
        }
    }

    var installDirectory: URL {
        AppPaths.translatorsDirectory.appendingPathComponent(rawValue.uppercased(), isDirectory: true)
    }

    static func from(_ backend: GraphicsBackend) -> GraphicsTranslator? {
        switch backend {
        case .dxvk: .dxvk
        case .dxmt: .dxmt
        default: nil
        }
    }
}

import Foundation

enum RuntimeFamily: String, Equatable {
    case gptk   // Apple Game Porting Toolkit (D3DMetal, fast; old Wine base)
    case wine   // mainline Wine for macOS (newer Wine; DXVK/wined3d, slower)
}

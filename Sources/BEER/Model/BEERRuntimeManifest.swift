import Foundation

/// `beer-runtime.json` at the root of a runtime BEER built itself
/// (scripts/build_gptk_runtime.sh). Marks it as BEER's own build, which new
/// games prefer, and says which macOS it needs.
struct BEERRuntimeManifest: Codable, Equatable {
    static let fileName = "beer-runtime.json"

    let d3dMetalVersion: String
    let crossOverSourceVersion: String
    let minimumMacOS: Int
}

import Foundation

extension ToolchainDetector {
    /// New game bottles default to GPTK (fastest, D3DMetal). Managed GPTK
    /// runtimes are named "Managed GPTK-…" but resolve to a wine64 executable
    /// (kind .systemWine), so match by name as well as kind. Falls back to the
    /// first available runtime.
    var preferredGameRuntime: RuntimeCandidate? {
        candidates.first { $0.displayName.localizedCaseInsensitiveContains("GPTK") || $0.displayName.localizedCaseInsensitiveContains("Game Porting") }
            ?? candidates.first { $0.kind == .gamePortingToolkit }
            ?? candidates.first
    }
}

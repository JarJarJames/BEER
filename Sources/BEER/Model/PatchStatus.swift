import Foundation

/// Whether the Steam emulator is patched into a game's install directory.
enum PatchStatus: Equatable {
    case applied            // .original files present alongside stubs
    case notApplied         // steam_api*.dll present but no .original
    case noDLLsFound        // game doesn't use Steamworks
    case installDirMissing  // can't read install dir

    /// Walks the whole install tree, so call it off the main actor.
    nonisolated static func probe(at installDir: URL?) -> PatchStatus {
        guard let installDir,
              let enumerator = FileManager.default.enumerator(
                  at: installDir, includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else {
            return .installDirMissing
        }
        var anyDLL = false
        for case let url as URL in enumerator {
            switch url.lastPathComponent.lowercased() {
            case "steam_api.dll.original", "steam_api64.dll.original":
                return .applied          // terminal — no need to walk the rest
            case "steam_api.dll", "steam_api64.dll":
                anyDLL = true
            default:
                break
            }
        }
        return anyDLL ? .notApplied : .noDLLsFound
    }
}
